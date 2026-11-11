module.exports = async function (context, req) {
    context.log('Simple test function called');
    
    context.res = {
        status: 200,
        body: "Hello from Azure Function!"
    };
};
