package com.example.app_limiter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * A minimal [VpnService] that filters adult / explicit websites at the DNS
 * layer. It captures only DNS traffic through a tiny local tunnel and forwards
 * every query to a family-filtering upstream resolver (Cloudflare for Families
 * `1.1.1.3`), which performs the actual content filtering. All other traffic is
 * untouched, so there is no blocklist to maintain and no packet inspection
 * beyond what's needed to forward DNS.
 *
 * The tunnel routes only [DNS_PROXY_ADDRESS] into itself (via `addDnsServer` +
 * a single-host route), so the OS sends DNS here while everything else bypasses
 * the VPN entirely.
 */
class WebFilterVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var scope: CoroutineScope? = null
    private val writeLock = Any()

    companion object {
        const val ACTION_STOP = "com.example.app_limiter.STOP_WEB_FILTER"

        private const val CHANNEL_ID = "WebFilterVpnService_Channel_ID"
        private const val NOTIFICATION_ID = 2

        private const val TUN_ADDRESS = "10.111.222.1"
        private const val DNS_PROXY_ADDRESS = "10.111.222.2"
        private val UPSTREAM_DNS = listOf("1.1.1.3", "1.0.0.3")
        private const val MTU = 1500
        private const val UPSTREAM_TIMEOUT_MS = 5000
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopFilter()
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundNotification()
        if (vpnInterface == null) {
            startFilter()
        }
        return START_STICKY
    }

    private fun startFilter() {
        val tun = Builder()
            .addAddress(TUN_ADDRESS, 32)
            .addDnsServer(DNS_PROXY_ADDRESS)
            .addRoute(DNS_PROXY_ADDRESS, 32)
            .setMtu(MTU)
            .setBlocking(true)
            .setSession("Shukr Web Filter")
            .establish() ?: run {
                stopSelf()
                return
            }
        vpnInterface = tun
        setEnabledFlag(true)

        val job = Job()
        val vpnScope = CoroutineScope(Dispatchers.IO + job)
        scope = vpnScope
        vpnScope.launch { runPacketLoop(tun) }
    }

    private fun runPacketLoop(tun: ParcelFileDescriptor) {
        val input = FileInputStream(tun.fileDescriptor)
        val output = FileOutputStream(tun.fileDescriptor)
        val buffer = ByteArray(MTU)

        while (scope?.isActive == true) {
            val length = try {
                input.read(buffer)
            } catch (e: Exception) {
                break
            }
            if (length <= 0) continue

            val packet = buffer.copyOf(length)
            if (!isDnsQuery(packet)) continue

            scope?.launch { handleDnsQuery(packet, output) }
        }
    }

    /** True for an IPv4 UDP packet destined for port 53. */
    private fun isDnsQuery(packet: ByteArray): Boolean {
        if (packet.size < 28) return false
        val version = (packet[0].toInt() and 0xF0) shr 4
        if (version != 4) return false
        if ((packet[9].toInt() and 0xFF) != 17) return false // UDP
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (packet.size < ihl + 8) return false
        val destPort = readUShort(packet, ihl + 2)
        return destPort == 53
    }

    private suspend fun handleDnsQuery(packet: ByteArray, output: FileOutputStream) {
        val ihl = (packet[0].toInt() and 0x0F) * 4
        val srcIp = packet.copyOfRange(12, 16)
        val dstIp = packet.copyOfRange(16, 20)
        val srcPort = readUShort(packet, ihl)
        val dnsPayload = packet.copyOfRange(ihl + 8, packet.size)

        val response = forwardToUpstream(dnsPayload) ?: return
        val reply = buildResponsePacket(
            sourceIp = dstIp,
            destIp = srcIp,
            sourcePort = 53,
            destPort = srcPort,
            dnsPayload = response,
        )
        synchronized(writeLock) {
            try {
                output.write(reply)
                output.flush()
            } catch (_: Exception) {
            }
        }
    }

    /** Sends the DNS query to a family-filtering resolver and returns its reply. */
    private fun forwardToUpstream(query: ByteArray): ByteArray? {
        for (server in UPSTREAM_DNS) {
            try {
                DatagramSocket().use { socket ->
                    protect(socket)
                    socket.soTimeout = UPSTREAM_TIMEOUT_MS
                    val address = InetAddress.getByName(server)
                    socket.send(DatagramPacket(query, query.size, address, 53))
                    val responseBuffer = ByteArray(MTU)
                    val response = DatagramPacket(responseBuffer, responseBuffer.size)
                    socket.receive(response)
                    return responseBuffer.copyOf(response.length)
                }
            } catch (_: Exception) {
                // Try the next resolver.
            }
        }
        return null
    }

    /** Wraps a DNS reply payload in a fresh IPv4 + UDP packet for the tunnel. */
    private fun buildResponsePacket(
        sourceIp: ByteArray,
        destIp: ByteArray,
        sourcePort: Int,
        destPort: Int,
        dnsPayload: ByteArray,
    ): ByteArray {
        val totalLength = 20 + 8 + dnsPayload.size
        val packet = ByteArray(totalLength)

        // IPv4 header.
        packet[0] = 0x45.toByte() // version 4, IHL 5
        packet[1] = 0
        writeUShort(packet, 2, totalLength)
        writeUShort(packet, 4, 0) // identification
        writeUShort(packet, 6, 0) // flags + fragment offset
        packet[8] = 64 // TTL
        packet[9] = 17 // UDP
        writeUShort(packet, 10, 0) // checksum placeholder
        System.arraycopy(sourceIp, 0, packet, 12, 4)
        System.arraycopy(destIp, 0, packet, 16, 4)
        writeUShort(packet, 10, checksum(packet, 0, 20))

        // UDP header (checksum 0 = not computed, valid for IPv4).
        val udpLength = 8 + dnsPayload.size
        writeUShort(packet, 20, sourcePort)
        writeUShort(packet, 22, destPort)
        writeUShort(packet, 24, udpLength)
        writeUShort(packet, 26, 0)

        System.arraycopy(dnsPayload, 0, packet, 28, dnsPayload.size)
        return packet
    }

    private fun readUShort(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 8) or (bytes[offset + 1].toInt() and 0xFF)
    }

    private fun writeUShort(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = ((value shr 8) and 0xFF).toByte()
        bytes[offset + 1] = (value and 0xFF).toByte()
    }

    /** Standard one's-complement Internet checksum. */
    private fun checksum(bytes: ByteArray, offset: Int, length: Int) : Int {
        var sum = 0
        var i = offset
        val end = offset + length
        while (i < end - 1) {
            sum += readUShort(bytes, i)
            i += 2
        }
        if (i < end) {
            sum += (bytes[i].toInt() and 0xFF) shl 8
        }
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv() and 0xFFFF
    }

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Web Filter",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Web filter active")
            .setContentText("Blocking adult & explicit websites")
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopFilter() {
        setEnabledFlag(false)
        scope?.cancel()
        scope = null
        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null
    }

    private fun setEnabledFlag(enabled: Boolean) {
        getSharedPreferences(AppLimiterPlugin.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(AppLimiterPlugin.KEY_WEB_FILTER_ENABLED, enabled)
            .apply()
    }

    override fun onDestroy() {
        stopFilter()
        super.onDestroy()
    }
}
