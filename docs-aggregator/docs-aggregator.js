const openApiDocs = [
    {
        name: "Transaction Service",
        url: `${window.location.origin}/api/transaction-service/v3/api-docs`,
    },
    {
        name: "Currency Service",
        url: `${window.location.origin}/api/currency-service/v3/api-docs`,
    },
];

window.addEventListener("DOMContentLoaded", () => {
    SwaggerUIBundle({
        urls: openApiDocs,
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [
            SwaggerUIBundle.presets.apis,
            SwaggerUIStandalonePreset,
        ],
        plugins: [
            SwaggerUIBundle.plugins.DownloadUrl,
        ],
        layout: "StandaloneLayout",
        tryItOutEnabled: false,
        supportedSubmitMethods: [],
    });
});
