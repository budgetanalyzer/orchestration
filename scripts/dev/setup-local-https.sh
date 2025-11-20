#!/bin/bash
set -e

echo "=== Budget Analyzer - Local HTTPS Setup ==="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERTS_DIR="$ORCHESTRATION_DIR/nginx/certs"

# Detect OS
case "$OSTYPE" in
    darwin*)  OS="macos" ;;
    linux*)   OS="linux" ;;
    msys*|cygwin*|win32*) OS="windows" ;;
    *)        OS="unknown" ;;
esac

echo "Detected OS: $OS"
echo

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "mkcert is not installed"
    echo
    echo "Install mkcert:"
    echo "  macOS:   brew install mkcert nss"
    echo "  Linux:   sudo apt install libnss3-tools && curl -JLO https://dl.filippo.io/mkcert/latest?for=linux/amd64 && chmod +x mkcert-* && sudo mv mkcert-* /usr/local/bin/mkcert"
    echo "  Windows: choco install mkcert"
    echo
    exit 1
fi

echo "[OK] mkcert is installed"

# Check for certutil on Linux (required for browser trust)
if [ "$OS" = "linux" ]; then
    if ! command -v certutil &> /dev/null; then
        echo "[ERROR] certutil not found - required for browser certificate trust"
        echo
        echo "Install with:"
        echo "  Ubuntu/Debian: sudo apt install libnss3-tools"
        echo "  Fedora/RHEL:   sudo dnf install nss-tools"
        echo "  Arch:          sudo pacman -S nss"
        echo
        exit 1
    fi
    echo "[OK] certutil is installed"
fi

# Install local CA
echo
echo "Installing local CA..."

CA_ROOT="$(mkcert -CAROOT)"
CA_FILE="$CA_ROOT/rootCA.pem"

if [ "$OS" = "linux" ]; then
    # Linux: Install to NSS trust stores (browsers) - no sudo needed
    echo "Installing CA to browser trust stores (NSS)..."
    TRUST_STORES=nss mkcert -install

    # Handle snap-installed Chromium (uses isolated NSS database)
    SNAP_CHROMIUM_NSS="$HOME/snap/chromium/current/.pki/nssdb"
    if [ -d "$SNAP_CHROMIUM_NSS" ]; then
        # Check if already installed
        if ! certutil -d sql:$SNAP_CHROMIUM_NSS -L 2>/dev/null | grep -q "mkcert"; then
            echo "Installing CA to snap Chromium..."
            certutil -d sql:$SNAP_CHROMIUM_NSS -A -t "C,," -n "mkcert" -i "$CA_FILE" && \
                echo "[OK] CA installed to snap Chromium" || \
                echo "[WARN] Failed to install CA to snap Chromium"
        else
            echo "[SKIP] CA already in snap Chromium"
        fi
    fi

    # Handle snap-installed Firefox (uses isolated profile directories)
    SNAP_FIREFOX_DIR="$HOME/snap/firefox/common/.mozilla/firefox"
    if [ -d "$SNAP_FIREFOX_DIR" ]; then
        for profile in "$SNAP_FIREFOX_DIR"/*.default* "$SNAP_FIREFOX_DIR"/*.default-release*; do
            if [ -d "$profile" ]; then
                profile_name=$(basename "$profile")
                if ! certutil -d sql:$profile -L 2>/dev/null | grep -q "mkcert"; then
                    echo "Installing CA to snap Firefox profile ($profile_name)..."
                    certutil -d sql:$profile -A -t "C,," -n "mkcert" -i "$CA_FILE" && \
                        echo "[OK] CA installed to snap Firefox" || \
                        echo "[WARN] Failed to install CA to snap Firefox"
                else
                    echo "[SKIP] CA already in snap Firefox ($profile_name)"
                fi
            fi
        done
    fi

    # Handle native Firefox profiles (non-snap)
    NATIVE_FIREFOX_DIR="$HOME/.mozilla/firefox"
    if [ -d "$NATIVE_FIREFOX_DIR" ]; then
        for profile in "$NATIVE_FIREFOX_DIR"/*.default* "$NATIVE_FIREFOX_DIR"/*.default-release*; do
            if [ -d "$profile" ]; then
                profile_name=$(basename "$profile")
                if ! certutil -d sql:$profile -L 2>/dev/null | grep -q "mkcert"; then
                    echo "Installing CA to native Firefox profile ($profile_name)..."
                    certutil -d sql:$profile -A -t "C,," -n "mkcert" -i "$CA_FILE" 2>/dev/null && \
                        echo "[OK] CA installed to native Firefox" || true
                fi
            fi
        done
    fi

elif [ "$OS" = "macos" ]; then
    # macOS: Install to system keychain
    mkcert -install

elif [ "$OS" = "windows" ]; then
    # Windows: Install to system store
    mkcert -install

else
    echo "[WARN] Unknown OS, attempting default installation..."
    mkcert -install
fi

echo "[OK] Local CA installed ($CA_ROOT)"
echo
echo "[NOTE] Restart your browser for certificate changes to take effect"

# Create certs directory
mkdir -p "$CERTS_DIR"
cd "$CERTS_DIR"

# Generate certificates
echo
echo "Generating wildcard certificate for *.budgetanalyzer.localhost..."

if [ -f "_wildcard.budgetanalyzer.localhost.pem" ]; then
    echo "[SKIP] Certificate already exists"
    echo "       To regenerate: rm $CERTS_DIR/_wildcard.budgetanalyzer.localhost*.pem"
else
    mkcert "*.budgetanalyzer.localhost"
    echo "[OK] Certificate generated"
fi

# Show certificate files
echo
echo "Certificate files:"
ls -lh "$CERTS_DIR"/_wildcard.budgetanalyzer.localhost*.pem 2>/dev/null || echo "  (none found)"

# Add CA to JVM truststore for Session Gateway
echo
echo "=== JVM Truststore Setup ==="
echo
echo "Session Gateway needs to trust the mkcert CA when calling api.budgetanalyzer.localhost"
echo

# Function to find JAVA_HOME cross-platform
find_java_home() {
    # If JAVA_HOME is already set and valid, use it
    if [ -n "$JAVA_HOME" ] && [ -d "$JAVA_HOME" ]; then
        echo "$JAVA_HOME"
        return 0
    fi

    # Try to detect from java command using java properties (most reliable)
    if command -v java &> /dev/null; then
        local java_home_prop
        java_home_prop=$(java -XshowSettings:properties -version 2>&1 | grep 'java.home' | awk -F' = ' '{print $2}')
        if [ -n "$java_home_prop" ] && [ -d "$java_home_prop" ]; then
            # java.home points to JRE, we may need to go up one level for JDK
            if [ -d "$java_home_prop/lib/security" ]; then
                echo "$java_home_prop"
                return 0
            elif [ -d "$(dirname "$java_home_prop")/lib/security" ]; then
                echo "$(dirname "$java_home_prop")"
                return 0
            fi
            echo "$java_home_prop"
            return 0
        fi
    fi

    # Check common locations
    local common_paths=(
        # SDKMan
        "$HOME/.sdkman/candidates/java/current"
        # Homebrew on Apple Silicon
        "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
        "/opt/homebrew/opt/openjdk"
        # Homebrew on Intel Mac
        "/usr/local/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
        "/usr/local/opt/openjdk"
        # Ubuntu/Debian alternatives
        "/usr/lib/jvm/default-java"
        "/usr/lib/jvm/java-17-openjdk-amd64"
        "/usr/lib/jvm/java-21-openjdk-amd64"
        "/usr/lib/jvm/java-11-openjdk-amd64"
        # Fedora/RHEL
        "/usr/lib/jvm/java"
        # Generic Linux
        "/usr/lib/jvm/default"
    )

    for path in "${common_paths[@]}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# Function to find cacerts file
find_cacerts() {
    local java_home="$1"

    # Standard location
    local standard="$java_home/lib/security/cacerts"
    if [ -f "$standard" ]; then
        # Follow symlinks to get actual file
        if [ "$OS" = "macos" ]; then
            # macOS doesn't have readlink -f, but we can use this
            echo "$standard"
        else
            readlink -f "$standard" 2>/dev/null || echo "$standard"
        fi
        return 0
    fi

    # JDK 8 and earlier location
    local jre_location="$java_home/jre/lib/security/cacerts"
    if [ -f "$jre_location" ]; then
        echo "$jre_location"
        return 0
    fi

    # Ubuntu/Debian system-wide cacerts (often symlinked)
    if [ -f "/etc/ssl/certs/java/cacerts" ]; then
        echo "/etc/ssl/certs/java/cacerts"
        return 0
    fi

    return 1
}

# Find Java installation
DETECTED_JAVA_HOME=$(find_java_home)

if [ -z "$DETECTED_JAVA_HOME" ]; then
    echo "[ERROR] Java installation not found"
    echo
    echo "Please ensure Java is installed and either:"
    echo "  1. Set JAVA_HOME environment variable, or"
    echo "  2. Have 'java' in your PATH"
    echo
    echo "After installing Java, re-run this script or manually add the CA:"
    echo
    echo "  sudo keytool -importcert -file \"$CA_FILE\" \\"
    echo "    -alias mkcert -keystore \$JAVA_HOME/lib/security/cacerts \\"
    echo "    -storepass changeit -noprompt"
    echo
    exit 1
fi

echo "Found Java installation: $DETECTED_JAVA_HOME"

# Find cacerts file
CACERTS=$(find_cacerts "$DETECTED_JAVA_HOME")

if [ -z "$CACERTS" ] || [ ! -f "$CACERTS" ]; then
    echo "[ERROR] Could not find cacerts file"
    echo "  Searched in: $DETECTED_JAVA_HOME/lib/security/cacerts"
    echo
    echo "You may need to manually add the CA to JVM truststore:"
    echo
    echo "  sudo keytool -importcert -file \"$CA_FILE\" \\"
    echo "    -alias mkcert -keystore <path-to-cacerts> \\"
    echo "    -storepass changeit -noprompt"
    echo
    exit 1
fi

echo "Found cacerts: $CACERTS"

if [ ! -f "$CA_FILE" ]; then
    echo "[ERROR] mkcert CA not found at: $CA_FILE"
    echo "  Run 'mkcert -install' first"
    exit 1
fi

# Check if already imported
if keytool -list -keystore "$CACERTS" -storepass changeit -alias mkcert &>/dev/null; then
    echo "[SKIP] mkcert CA already in JVM truststore"
else
    echo
    echo "Adding mkcert CA to JVM truststore..."
    echo "  CA file:  $CA_FILE"
    echo "  Keystore: $CACERTS"
    echo

    # Determine if we need sudo (check if we can write to cacerts)
    if [ -w "$CACERTS" ]; then
        KEYTOOL_CMD="keytool"
    else
        echo "  (requires sudo for write access to cacerts)"
        KEYTOOL_CMD="sudo keytool"
    fi

    # Import the certificate
    if $KEYTOOL_CMD -importcert -file "$CA_FILE" \
        -alias mkcert \
        -keystore "$CACERTS" \
        -storepass changeit \
        -noprompt; then
        echo
        echo "[OK] mkcert CA added to JVM truststore"
    else
        echo
        echo "[ERROR] Failed to add CA to JVM truststore"
        echo
        echo "Try running manually:"
        echo
        echo "  sudo keytool -importcert -file \"$CA_FILE\" \\"
        echo "    -alias mkcert -keystore \"$CACERTS\" \\"
        echo "    -storepass changeit -noprompt"
        echo
        exit 1
    fi

    # Verify the import
    echo
    echo "Verifying import..."
    if keytool -list -keystore "$CACERTS" -storepass changeit -alias mkcert &>/dev/null; then
        echo "[OK] Certificate verified in truststore"
    else
        echo "[ERROR] Certificate verification failed - import may not have succeeded"
        exit 1
    fi
fi

echo
echo "=== Setup Complete! ==="
echo
echo "Next steps:"
echo "1. Restart your browser (required for certificate changes)"
echo "2. Start NGINX:           docker compose up -d api-gateway"
echo "3. Start Session Gateway: cd ../session-gateway && ./gradlew bootRun"
echo "4. Access application:    https://app.budgetanalyzer.localhost"
echo "5. Test API Gateway:      curl https://api.budgetanalyzer.localhost/health"
echo
