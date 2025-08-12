import requests

url = "http://example.com/api"
cookies = {
    "session_id": "123456",
    "user_name": "john\\doe",
}

headers = {
    "Host": "example.com"
}

res = requests.get(url, headers=headers, cookies=cookies)
print(res.text)
