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
            var release = metadata.release || {};
            var version = release.version || "unknown";
            var imageTag = release.imageTag || "unknown";

            label.textContent = "Release " + version;
            label.title = "Image tag " + imageTag;
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
