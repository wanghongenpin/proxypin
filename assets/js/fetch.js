function fetch(url, options) {
    options = options || {};
    return new Promise((resolve, reject) => {
        const request = new XMLHttpRequest();
        const keys = [];
        const all = [];
        const headers = {};

        const response = () => ({
            ok: (request.status / 100 | 0) === 2,		// 200-299
            statusText: request.statusText,
            status: request.status,
            url: request.responseURL,
            body: request.response.body,
            text: () => Promise.resolve(request.responseText),
            json: () => {
                // TODO: review this handle because it may discard \n from json attributes
                try {
                    // console.log('RESPONSE TEXT IN FETCH: ' + request.responseText);
                    return Promise.resolve(JSON.parse(request.responseText));
                } catch (e) {
                    // console.log('ERROR on fetch parsing JSON: ' + e.message);
                    return Promise.resolve(request.responseText);
                }
            },

            blob: () => Promise.resolve(request.response.body),
            clone: response,
            headers: {
                keys: () => keys,
                entries: () => all,
                get: n => headers[n.toLowerCase()],
                has: n => n.toLowerCase() in headers
            }
        });

        request.open(options.method || 'get', url, true);

        request.onload = () => {
            request.getAllResponseHeaders().replace(/^(.*?):[^\S\n]*([\s\S]*?)$/gm, (m, key, value) => {
                keys.push(key = key.toLowerCase());
                all.push([key, value]);
                headers[key] = headers[key] ? `${headers[key]},${value}` : value;
            });
            resolve(response());
        };

        request.onerror = reject;

        request.withCredentials = options.credentials == 'include';

        if (options.headers) {
            if (options.headers.constructor.name == 'Object') {
                for (const i in options.headers) {
                    request.setRequestHeader(i, options.headers[i]);
                }
            } else { // if it is some Headers pollyfill, the way to iterate is through for of
                for (const header of options.headers) {
                    request.setRequestHeader(header[0], header[1]);
                }
            }
        }

        request.send(options.body || null);
    });
}