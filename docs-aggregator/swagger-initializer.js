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

var LOCAL_TABLE_COLUMNS = [
    "Repository",
    "Version",
    "Commit",
    "Branch",
    "Committed",
    "Shared library"
];

function localDescribeLabel(source) {
    if (!source.tag) {
        return "untagged";
    }

    if (source.commitsSinceTag) {
        return source.tag + "+" + source.commitsSinceTag;
    }

    return source.tag;
}

function dirtySuffix(source) {
    return source.dirty ? " \u00b7 dirty" : "";
}

function localOrchestrationLabel(value) {
    if (!value || value.status !== "ok") {
        return "unknown";
    }

    return (value.version || "untagged") + " @ " + (value.shortCommit || "unknown") + dirtySuffix(value);
}

function localSharedLibraryLabel(value) {
    if (!value || value.status !== "ok") {
        return "unknown";
    }

    return (value.version || "unknown") + " \u00b7 " + localDescribeLabel(value) + " @ " +
        (value.shortCommit || "unknown") + dirtySuffix(value);
}

function localServiceCommonLabel(repository, sharedLibrary) {
    var serviceCommon = repository.serviceCommon;

    if (!serviceCommon) {
        return "n/a";
    }

    if (serviceCommon.matchesLocalCheckout) {
        return (serviceCommon.declared || "unknown") + " (local checkout)";
    }

    return (serviceCommon.declared || "unknown") + " (not local; checkout is " +
        ((sharedLibrary && sharedLibrary.version) || "unknown") + ")";
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

function activeColumnCount() {
    var header = document.getElementById("deployment-artifacts-header");

    if (header && header.children.length) {
        return header.children.length;
    }

    return 7;
}

function appendMessageRow(tbody, message) {
    var row = document.createElement("tr");
    var cell = document.createElement("td");

    cell.colSpan = activeColumnCount();
    cell.textContent = message;
    row.appendChild(cell);
    tbody.appendChild(row);
}

function renderLocalTableHeader() {
    var header = document.getElementById("deployment-artifacts-header");
    var index;
    var cell;

    if (!header) {
        return;
    }

    header.textContent = "";

    for (index = 0; index < LOCAL_TABLE_COLUMNS.length; index += 1) {
        cell = document.createElement("th");
        cell.scope = "col";
        cell.textContent = LOCAL_TABLE_COLUMNS[index];
        header.appendChild(cell);
    }
}

function renderLocalRepositories(metadata) {
    var tbody = document.getElementById("deployment-artifacts");
    var repositories = metadata.repositories || {};
    var names = orderedArtifactNames(repositories);
    var renderedCount = 0;
    var index;
    var name;
    var repository;
    var row;

    if (!tbody) {
        return;
    }

    tbody.textContent = "";

    for (index = 0; index < names.length; index += 1) {
        name = names[index];
        repository = repositories[name];

        if (!repository) {
            continue;
        }

        row = document.createElement("tr");
        if (repository.dirty) {
            row.className = "deployment-row-dirty";
        }
        appendCell(row, name, "deployment-runtime");

        if (repository.status !== "ok") {
            appendCell(row, "missing repo", "deployment-ref");
            appendCell(row, "unknown", "");
            appendCell(row, "unknown", "");
            appendCell(row, "unknown", "");
            appendCell(row, "unknown", "");
        } else {
            appendCell(row, (repository.version || "untagged") + dirtySuffix(repository), "deployment-ref");
            appendCell(row, repository.shortCommit, "", repository.commit);
            appendCell(row, repository.branch, "");
            appendCell(row, repository.commitDate, "");
            appendCell(row, localServiceCommonLabel(repository, metadata.sharedLibrary), "");
        }

        tbody.appendChild(row);
        renderedCount += 1;
    }

    if (renderedCount === 0) {
        appendMessageRow(tbody, "No local repositories found");
    }
}

function renderLocalMetadata(metadata, label) {
    var deployment = metadata.deployment || {};
    var summary = "Tilt local development";
    var caption = "Local repository state at Tilt start";

    if (label) {
        label.textContent = summary;
        label.title = caption;
        label.classList.remove("docs-release-muted");
    }

    setElementText("deployment-summary", summary);
    setElementText("deployment-artifacts-caption", caption);
    setElementText("deployment-environment", deployment.environment || "unknown");
    setElementText("deployment-orchestration", localOrchestrationLabel(metadata.orchestration));
    setElementText("deployment-shared-library", localSharedLibraryLabel(metadata.sharedLibrary));
    renderLocalTableHeader();
    renderLocalRepositories(metadata);
}

function hideSharedLibraryFact() {
    var fact = document.getElementById("deployment-shared-library-fact");

    if (fact) {
        fact.hidden = true;
    }
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
        appendMessageRow(tbody, "No deployment artifacts found");
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
            var summary = "Deployment " + version;

            if (deployment.runtime === "tilt") {
                renderLocalMetadata(metadata, label);
                return;
            }

            hideSharedLibraryFact();

            if (label) {
                label.textContent = summary;
                label.title = summary;
                label.classList.remove("docs-release-muted");
            }

            setElementText("deployment-summary", summary);
            setElementText("deployment-environment", environment);
            setElementText("deployment-orchestration", orchestrationLabel(orchestration));
            renderDeploymentArtifacts(metadata);
        })
        .catch(function() {
            var tbody = document.getElementById("deployment-artifacts");

            if (label) {
                label.textContent = "Release unavailable";
                label.title = "";
                label.classList.add("docs-release-muted");
            }

            setElementText("deployment-summary", "Deployment metadata unavailable");
            if (tbody) {
                tbody.textContent = "";
                appendMessageRow(tbody, "Deployment metadata unavailable");
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
