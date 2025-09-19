async function onRequest() {


    const fetchResponse = await fetch('https://httpbin.org/anything');
    console.log(fetchResponse.headers);
    console.log(await  fetchResponse.text());
    console.log(  fetchResponse.body);

    const response = {
        statusCode: 200,
        body: fetchResponse.body,
        headers: fetchResponse.headers
    };
    return response;
}

onRequest().then( response => {
    console.log('Response:', response);

})