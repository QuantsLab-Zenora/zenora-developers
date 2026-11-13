// Reference source, not device-compiled in this Windows milestone.
package dev.zenora.example

import android.content.Context
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.browser.customtabs.CustomTabsIntent
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private fun b64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
data class PendingSignIn(val state: String, val verifier: String, val redirect: String, val url: String) {
    companion object {
        fun create(): PendingSignIn {
            fun random() = b64(ByteArray(48).also { SecureRandom().nextBytes(it) })
            val state = random(); val verifier = random()
            val redirect = "https://account.zenora.dev/native/callback/android"
            val challenge = b64(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))
            val url = Uri.parse("https://account.zenora.dev/oauth/authorize").buildUpon()
                .appendQueryParameter("client_id", "zenora-android").appendQueryParameter("redirect_uri", redirect)
                .appendQueryParameter("response_type", "code").appendQueryParameter("code_challenge_method", "S256")
                .appendQueryParameter("code_challenge", challenge).appendQueryParameter("state", state)
                .appendQueryParameter("scope", "studio.read studio.write community.read community.write").build().toString()
            return PendingSignIn(state, verifier, redirect, url)
        }
    }
    fun open(context: Context) = CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url))
    fun code(callback: Uri): String {
        val clean = callback.buildUpon().clearQuery().fragment(null).build().toString()
        require(clean == redirect && callback.fragment == null)
        val returned = callback.getQueryParameters("state")
        require(returned.size == 1 && MessageDigest.isEqual(state.toByteArray(), returned.single().toByteArray()))
        require(callback.getQueryParameters("code").size == 1)
        return callback.getQueryParameter("code") ?: error("Missing authorization code")
    }
}

/** One encrypted item. Exclude this preference file from backups; never store keys in preferences. */
class TokenVault(context: Context) {
    private val preferences = context.getSharedPreferences("zenora_native_credentials", Context.MODE_PRIVATE)
    private val alias = "zenora.native.session"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
        }.generateKey()
    }
    @Synchronized fun save(value: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))
        check(preferences.edit().putString("sealed", b64(sealed)).commit())
    }
    @Synchronized fun load(): JSONObject? {
        val sealed = preferences.getString("sealed", null) ?: return null
        val bytes = Base64.decode(sealed, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
        return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    @Synchronized fun clear() { check(preferences.edit().clear().commit()) }
}

data class HttpResult(val status: Int, val bytes: ByteArray, val retryAfter: String?)
class ZenoraClient(private val origin: URI = URI("https://api.zenora.dev")) {
    // Run on Dispatchers.IO. No transport retries for mutations or refresh.
    fun request(method: String, path: String, access: String, body: ByteArray? = null, key: String? = null): HttpResult {
        require(path.startsWith("/v1/") && !path.contains('\\'))
        val url = origin.resolve(path); require(url.host == origin.host && url.scheme == origin.scheme && url.port == origin.port)
        val connection = url.toURL().openConnection() as HttpURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.requestMethod = method; connection.connectTimeout = 15000; connection.readTimeout = 30000
            connection.setRequestProperty("Authorization", "Bearer $access")
            connection.setRequestProperty("Accept", "application/json")
            key?.let { connection.setRequestProperty("Idempotency-Key", it) }
            if (body != null) {
                connection.doOutput = true; connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            val data = (if (status < 400) connection.inputStream else connection.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
            return HttpResult(status, data, connection.getHeaderField("Retry-After"))
        } finally { connection.disconnect() }
    }
    fun currentUser(access: String) = request("GET", "/v1/me", access)
    fun generate(access: String, savedBody: String, savedKey: String) = request("POST", "/v1/generations", access, savedBody.toByteArray(Charsets.UTF_8), savedKey)
    fun image(access: String, apiPath: String) = request("GET", apiPath, access).also { require(it.status == 200) }.bytes
}

/** Call the provided form exchange exactly once inside this monitor. Unknown outcome requires sign-in. */
class SerializedRefresh(private val vault: TokenVault) {
    @Synchronized fun refresh(expectedRefreshToken: String, exchange: (String) -> JSONObject): JSONObject {
        val current = vault.load() ?: error("Sign in required")
        if (current.getString("refresh_token") != expectedRefreshToken) return current
        return try { exchange(expectedRefreshToken).also { vault.save(it) } }
        catch (failure: Exception) { vault.clear(); throw failure }
    }
}
