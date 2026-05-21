function renderReleaseMetadata() {
    var label = document.getElementById("release-metadata-label");

    if (!label || !window.fetch) {
        return;
    }

    fetch("/api-docs/release-metadata.json", { cache: "no-store" })
        .then(function(response) {
            if (!response.ok) {
                throw new Error("release metadata unavailable");
            }
            return response.json();
        })
        .then(function(metadata) {
            var deployment = metadata.deployment || {};
            var release = metadata.release || {};
            var version = deployment.id || release.version || "unknown";
            var status = deployment.status || release.imageTag || "unknown";

            label.textContent = "Deployment " + version;
            label.title = "Status " + status;
            label.classList.remove("docs-release-muted");
        })
        .catch(function() {
            label.textContent = "Release unavailable";
            label.title = "";
            label.classList.add("docs-release-muted");
        });
}

window.onload = function() {
    renderReleaseMetadata();

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
