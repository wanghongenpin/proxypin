package com.network.proxy.root

import android.content.ContextWrapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RootProxyRulesTest {
    private val manager = RootProxyManager.instance

    private fun options(interfaces: List<String> = emptyList(), tether: Boolean = false) = RootProxyManager.Options(
        proxyHost = "127.0.0.1",
        proxyPort = 9099,
        allowApps = emptyList(),
        disallowApps = emptyList(),
        proxyPassDomains = listOf("10.0.0.0/8"),
        redirectPorts = listOf("80", "443"),
        blockIpv6 = true,
        blockQuic = true,
        localProxy = true,
        interfaces = interfaces,
        captureTether = tether,
        tetherInterfaces = if (tether) listOf("wlan2") else emptyList()
    )

    @Test
    fun allInterfacesHasNoOutMatch() {
        val rules = manager.buildRules(ContextWrapper(null), options())
        val redirect = rules.filter { it.contains("REDIRECT") }
        assertEquals(1, redirect.size)
        assertTrue(redirect[0].contains("-A PROXYPIN_OUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 9099"))
        assertTrue(rules.none { it.contains("PREROUTING") })
    }

    @Test
    fun selectedInterfacesAddOutMatch() {
        val rules = manager.buildRules(ContextWrapper(null), options(listOf("wlan0", "rmnet_data0", "bad;rm -rf")))
        val redirect = rules.filter { it.contains("REDIRECT") }
        assertEquals(listOf(" -o wlan0 ", " -o rmnet_data0 "), redirect.map { Regex(" -o \\S+ ").find(it)!!.value })
    }

    @Test
    fun tetherRulesUsePrerouting() {
        val rules = manager.buildRules(ContextWrapper(null), options(tether = true))
        val pre = rules.filter { it.contains("PROXYPIN_PRE") }
        assertTrue(pre.last().endsWith("-I PREROUTING -j PROXYPIN_PRE"))
        assertTrue(pre.any { it.contains("-A PROXYPIN_PRE -i wlan2 -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 9099") })
        assertTrue(pre.any { it.contains("-A PROXYPIN_PRE -i ap+ -p tcp") })
        assertTrue(pre.any { it.contains("-A PROXYPIN_PRE -d 10.0.0.0/8 -j RETURN") })
        // 输出到文件，便于在真实 iptables 上校验语法
        System.getenv("RULES_OUT")?.let { File(it).writeText(rules.joinToString("\n")) }
    }

    @Test
    fun conntrackParse() {
        val lines = listOf(
            "ipv4     2 udp      17 20 src=192.168.43.5 dst=8.8.8.8 sport=51234 dport=53 src=8.8.8.8 dst=192.168.43.5 sport=53 dport=51234 mark=0 zone=0 use=2",
            "ipv4     2 tcp      6 431999 ESTABLISHED src=192.168.43.5 dst=142.250.1.1 sport=51234 dport=8443 src=192.168.43.1 dst=192.168.43.5 sport=9099 dport=51234 [ASSURED] mark=0 zone=0 use=2",
        )
        val e = manager.parseConntrack(lines, 51234, 9099)!!
        assertEquals("142.250.1.1", e.remoteHost)
        assertEquals(8443, e.remotePort)
        assertEquals(-1, e.uid)
        assertNull(manager.parseConntrack(lines, 51234, 8888))
    }
}
