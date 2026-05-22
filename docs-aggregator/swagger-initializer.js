var DEPLOYMENT_ARTIFACT_ORDER = [
    "transaction-service",
    "currency-service",
    "permission-service",
    "session-gateway",
    "budget-analyzer-web",
    "ext-authz"
];

function imageLabel(value) {
    if (!value) {
        return "unknown";
    }

    return value;
}

function orchestrationLabel(value) {
    if (!value) {
        return "unknown";
    }

    if (!value.sourceRef && !value.commit) {
        return "unknown";
    }

    if (!value.sourceRef || value.sourceRef === value.commit) {
        return value.commit || value.sourceRef;
    }

    return value.sourceRef + " @ " + value.commit;
}

function setElementText(id, value) {
    var element = document.getElementById(id);

    if (element) {
        element.textContent = value;
    }
}

function appendCell(row, value, className, title) {
    var cell = document.createElement("td");
    var code;

    if (className) {
        cell.className = className;
    }

    if (title) {
        cell.title = title;
    }

    code = document.createElement("code");
    code.textContent = value || "unknown";
    cell.appendChild(code);
    row.appendChild(cell);
}

function orderedArtifactNames(artifacts) {
    var names = DEPLOYMENT_ARTIFACT_ORDER.slice();
    var name;

    for (name in artifacts) {
        if (Object.prototype.hasOwnProperty.call(artifacts, name) && names.indexOf(name) === -1) {
            names.push(name);
        }
    }

    return names;
}

function renderDeploymentArtifacts(metadata) {
    var tbody = document.getElementById("deployment-artifacts");
    var artifacts = metadata.artifacts || {};
    var names = orderedArtifactNames(artifacts);
    var renderedCount = 0;
    var index;
    var name;
    var artifact;
    var row;

    if (!tbody) {
        return;
    }

    tbody.textContent = "";

    for (index = 0; index < names.length; index += 1) {
        name = names[index];
        artifact = artifacts[name];

        if (!artifact) {
            continue;
        }

        row = document.createElement("tr");
        appendCell(row, name, "deployment-runtime");
        appendCell(row, artifact.sourceRepository, "");
        appendCell(row, artifact.artifactVersion, "");
        appendCell(row, artifact.sourceRef, "deployment-ref");
        appendCell(row, artifact.sourceCommit, "");
        appendCell(row, imageLabel(artifact.image), "deployment-image", artifact.image);
        appendCell(row, artifact.serviceCommonVersion || "n/a", "");
        tbody.appendChild(row);
        renderedCount += 1;
    }

    if (renderedCount === 0) {
        row = document.createElement("tr");
        row.appendChild(document.createElement("td"));
        row.firstChild.colSpan = 7;
        row.firstChild.textContent = "No deployment artifacts found";
        tbody.appendChild(row);
    }
}

function renderDeploymentMetadata() {
    var label = document.getElementById("release-metadata-label");

    if (!window.fetch) {
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
            var environment = deployment.environment || "unknown";
            var orchestration = deployment.orchestrationRepository || {};

            if (label) {
                label.textContent = "Deployment " + version;
                label.title = "Deployment " + version;
                label.classList.remove("docs-release-muted");
            }

            setElementText("deployment-summary", "Deployment " + version);
            setElementText("deployment-environment", environment);
            setElementText("deployment-orchestration", orchestrationLabel(orchestration));
            renderDeploymentArtifacts(metadata);
        })
        .catch(function() {
            var tbody = document.getElementById("deployment-artifacts");
            var row;
            var cell;

            if (label) {
                label.textContent = "Release unavailable";
                label.title = "";
                label.classList.add("docs-release-muted");
            }

            setElementText("deployment-summary", "Deployment metadata unavailable");
            if (tbody) {
                tbody.textContent = "";
                row = document.createElement("tr");
                cell = document.createElement("td");
                cell.colSpan = 7;
                cell.textContent = "Deployment metadata unavailable";
                row.appendChild(cell);
                tbody.appendChild(row);
            }
        });
}

window.onload = function() {
    renderDeploymentMetadata();

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
