import requests

url = 'https://yanchu.maoyan.com/my/odea/project/showsAndTickets?__reqTraceID=8E638678-8F0C-470E-B5EE-C96C6CD2A713&ax=187456255&bx=196397459&ci=73&cityId=73&clientPlatform=2&clientVersion=9.77.1&dpId=000000000000096E5325D2CA749CEB6BD3159B6850684A177423196309351149&language=zh_CN&optimus_code=10&optimus_risk_level=71&sellChannel=5&token=AgGlJLS8W3QMTfBVqiGuYpt89TP0BuO9XxhQjV22SpPleiCJx7bmuofe84qS6OOFLuTPyIPTRQk93gAAAAD8MgAAAE546kP4FSyLA1jD8WTciboX6AMj8vQFaOYgrAg7pOV-YVI6thXrHWNu4Tl0Hcbr&userid=477788341&utm_campaign=AmovieBmovieD200H0&utm_content=000000000000096E5325D2CA749CEB6BD3159B6850684A177423196309351149&utm_medium=iphone&utm_source=AppStore&utm_term=9.77.1&uuid=000000000000096E5325D2CA749CEB6BD3159B6850684A177423196309351149&version_name=9.77.1'

cookies = {
    'latlng': '34.74367%2C113.77073%2C1774278277594',
    'latlon': '34.74367%2C113.77073%2C1774278277595',
    'mt_c_token': 'AgGlJLS8W3QMTfBVqiGuYpt89TP0BuO9XxhQjV22SpPleiCJx7bmuofe84qS6OOFLuTPyIPTRQk93gAAAAD8MgAAAE546kP4FSyLA1jD8WTciboX6AMj8vQFaOYgrAg7pOV-YVI6thXrHWNu4Tl0Hcbr',
    'network': 'wifi',
    'token': 'AgGlJLS8W3QMTfBVqiGuYpt89TP0BuO9XxhQjV22SpPleiCJx7bmuofe84qS6OOFLuTPyIPTRQk93gAAAAD8MgAAAE546kP4FSyLA1jD8WTciboX6AMj8vQFaOYgrAg7pOV-YVI6thXrHWNu4Tl0Hcbr',
    '_utm_campaign': 'AmovieBmovieD200H0',
    '_utm_content': '000000000000096E5325D2CA749CEB6BD3159B6850684A177423196309351149',
    '_utm_medium': 'iphone',
    '_utm_source': 'AppStore',
    '_utm_term': '9.77.1',
    'cityid': '73',
    'dpid': '',
    'uuid': '000000000000096E5325D2CA749CEB6BD3159B6850684A177423196309351149',
}

headers = {
    'Host': 'yanchu.maoyan.com',
    'X-SAKHTTPCache-IgnoreQueryKey': '__reqTraceID',
    'Accept': '*/*',
    'userid': '477788341',
    'Accept-Language': 'zh-Hans-CN, en-CN, en-us;q=0.8',
    'pragma-os': 'MApi 1.1 (mtscope 9.77.1 appstore; iPhone 26.3.1 iPhone17,3; a0d0)',
    'M-TraceId': '3139937537927853169',
    'yodaReady': 'native',
    'User-Agent': 'ios/26.3.1 com.meituan.imovie/9.77.1 iPhone 16',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'mtgsig': '{"a0":"3.0","a1":"6fbc504c-38b0-43a6-a360-d961594a3b0d","a3":24,"a4":1774278278,"a5":"yuFmI2UNtNESnG6tkWEk4/JXYfsQvGgnqfn8pwk0Fp+0xcehn2cGFSC+gRjTBd82ep5Ve86998fJUFUfXVaJGrp45/29S0srb2R+QrkxEymHg/1NUh+ZPzjqL7GAkzKkUB59DML8WWCw8he3fqBFp0dMcd9Aca7qpY+pEyeZ1Qt9RKYSHTaaGbVhqgxLcS98dELSrQiavo/0TEA2TbDd9QzV7rt5uX+EYMryT1OYS+IKYDeRZUFstwdsg352WQfmx9BFp/LJ9CNOKKG/TN3t8txXvblZ8ZGSW01YzyZzYs9fpWflufudb/cJVz1esMaSiZPvvsjgZMwP1119HBJzlUpnUtd1O3yeFAuOjRXJanBEL53F6TUpCbiDoB3cMLjdEw==","a6":0,"a7":"DODmLnr7YTJ2DUxbeedDrS3dbWNG3HJDGHaz8vCmVEualBkF/xWVOSoKKoWKSFob5lmEIN/vycS5phpyIV2HGXzFhxkk0ddZdXODaJ5eo6Q=","a8":"37e2c13aaeb189a9acbd8018a8c4377c21bcf0b8d4ea88e224da8768","a9":"fbd4caf5AbMIhzxDUnD8OaVF7COmhJGlF772mvjVVvSjF6kOBU1Oip+jqclqRbiBiEq7rrMJ9xp23t4CoEb2v4GG7WbVtnQtQDDbzxOo5tD6RniFLdeDuqRGs/phdUDfgapqdy/P6bEpi/kgvEoIdJP6LmCv8HDpPqW1Q8tobTTeI3cIjwxkmr7XEWYEnf6ECxPtCvyLFjVv4umPzPUICRGjOG8zBp6/3eH3WhHaLIWEUEOfPflTE0eQGnNvuapVzywzZohomqPtuU2hpxx5kOMgCWiwHicPAYOnJcdor+IkwUUtsk4lfrmZsq/J/Ho187ZkMXbhv5Is81Ho61l+nSWZN8uwHjDAzK6yMjmvaJutQbIGJImTQMZmwWgLHqa/GxPIQkwMh08rA+mAXvFhm2M7ILtm9NiVtswU/54XxqcgsH71sAFkRlSX0Dc6+oRni0lNsGSi0Z46df+hWbJ9HXlJ4yFlBI6m81AmbJ4ZyTl1+1hkq2nfWJkgN2nfca5PpY7n/1GfrTGZLlUJD+TgyqGRZrF+Hqk8u7f/iX9RDS1EWvAoNxzat0/SVuEle9iHRsre4keB3asm6AG55T4B/HAEKKb2fVUucmVGEnSUKcPeonZUV6l7oGumKNrAty0CmhVJQON0/FZdLA2HXJMYPpIY+zhFhQ==","a10":"5,108,1.1.6","x0":2,"a2":"e937083ad80c1e27f20e8f1a8e78b630"}',
    'yodaVersion': '1.14.107.17',
    'SAKModelSDKVersionKey': '4.0.116',
}

json_data = {
    'projectId': 457744,
    'client': 2,
    'requestSource': 1,
}

response = requests.post(url, headers=headers, cookies=cookies, json=json_data)
print(response.text)
