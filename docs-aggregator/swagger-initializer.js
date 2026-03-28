window.onload = function() {
    window.ui = SwaggerUIBundle({
        url: "/api-docs/openapi.json",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [
            SwaggerUIBundle.presets.apis
        ],
        layout: "BaseLayout",
        supportedSubmitMethods: [],
        tryItOutEnabled: false,
        defaultModelsExpandDepth: 0,
        docExpansion: "list"
    });
};
