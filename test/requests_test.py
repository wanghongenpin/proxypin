import requests

url = "https://h5api.m.taobao.com/h5/mtop.mediaplatform.live.check.info/2.0/?jsv=2.7.0&appKey=25278248&t=1732545137533&sign=b71dc9348c00e460e7db0dba8b513495&api=mtop.mediaplatform.live.check.info&v=2.0&appVersion=7.9.0&needLogin=true&type=jsonp&dataType=jsonp&callback=mtopjsonp6763&data=%7B%22liveId%22%3A%22495202688287%22%7D"
cookies = {
    "_samesite_flag_": "true",
    "3PcFlag": "1732539699265",
    "cookie2": "2c97dd390875418088acaa436b687cc4",
    "t": "212cdd2cad20329e374764f215e28d33",
    "_tb_token_": "f54f43ea53973",
    "cna": "MxXLH2+8sn4BASQIiAaiRXvA",
    "xlly_s": "1",
    "sgcookie": "E100eCj3Vo3hPWjpiAQHe9Vdpf%2FU1q56ubBnkTao3MLYNOwCDJMIoxNP0N95EDJCMbLAGtlajDN6h4kOPL5irIRnvzXL%2FdwWk0odkxb0q0OYr9I%3D",
    "wk_cookie2": "1c385564ef446df05a58aab8a797594e",
    "wk_unb": "UUpgQcERb4upQSXAhw%3D%3D",
    "unb": "2217346076826",
    "csg": "9b8d1f42",
    "lgc": "%5Cu4F1A%5Cu751F88f",
    "cancelledSubSites": "empty",
    "cookie17": "UUpgQcERb4upQSXAhw%3D%3D",
    "dnk": "%5Cu4F1A%5Cu751F88f",
    "skt": "fb8ebd9e1cdb4de1",
    "existShop": "MTczMjUzOTc4OQ%3D%3D",
    "tracknick": "%5Cu4F1A%5Cu751F88f",
    "_cc_": "V32FPkk%2Fhw%3D%3D",
    "_l_g_": "Ug%3D%3D",
    "sg": "f64",
    "_nk_": "%5Cu4F1A%5Cu751F88f",
    "cookie1": "VFQmwCET8bF7o5l%2BzlwVznTxRGu9ynM%2FsGiPW5MQBFU%3D",
    "_m_h5_tk": "6459e3cd4d54401ea1cb2eac7bcc378e_1732548069723",
    "_m_h5_tk_enc": "6c112cba6d346180d67cd9c6492fdef4",
    "isg": "BAkJZPdMivyidHYIXlTZBDrrGDVjVv2I8uSScqt-hfAv8ikE86YNWPegMF7EsZXA",
}

headers = {
    "Host": "h5api.m.taobao.com",
    "Connection": "keep-alive",
    "Accept": "*/*",
    "Accept-Encoding": "gzip, deflate, br",
    "Accept-Language": "en-US",
    "Origin": "https://liveplatform.taobao.com",
    "Referer": "https://liveplatform.taobao.com",
    "Sec-Fetch-Dest": "script",
    "Sec-Fetch-Mode": "no-cors",
    "Sec-Fetch-Site": "cross-site",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) live-anchor-workbench/7.9.0 Chrome/106.0.5249.199 Electron/21.4.4 Safari/537.36 12574478.live-anchor-workbench.electron",
    "sec-ch-ua": "\"Not;A=Brand\";v=\"99\", \"Chromium\";v=\"106\"",
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": "\"Windows\""
}

res = requests.get(url, headers=headers, cookies=cookies)
print(res.text)
