#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRISMA_DIR="${PROJECT_DIR}/backend/prisma"
SCHEMA_FILE="${PRISMA_DIR}/schema.prisma"
MIGRATIONS_DIR="${PRISMA_DIR}/migrations"

echo "=== ExcaliDash Migration Generator ==="
echo ""
echo "Select database provider:"
echo "1) SQLite"
echo "2) PostgreSQL"
echo ""
read -p "Enter choice (1 or 2): " choice

case "$choice" in
    1)
        PROVIDER="sqlite"
        ;;
    2)
        PROVIDER="postgresql"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "Provider selected: ${PROVIDER}"

OTHER_PROVIDER=$([ "$PROVIDER" = "sqlite" ] && echo "postgresql" || echo "sqlite")

# Check if provider folder exists
if [ ! -d "${MIGRATIONS_DIR}/${PROVIDER}" ]; then
    echo "ERROR: Migrations folder for '${PROVIDER}' does not exist at ${MIGRATIONS_DIR}/${PROVIDER}"
    exit 1
fi

echo ""
echo "Step 1: Backing up schema.prisma..."

# Backup current schema.prisma
cp "${SCHEMA_FILE}" "${SCHEMA_FILE}.backup"

echo ""
echo "Step 2: Updating schema.prisma to use ${PROVIDER}..."

# Update schema.prisma to use the selected provider
sed -i 's/provider = env("DATABASE_PROVIDER")/provider = "'"${PROVIDER}"'"/' "${SCHEMA_FILE}"

echo ""
echo "Step 3: Setting up migrations..."

# Clear migrations folder
rm -rf "${MIGRATIONS_DIR}"/*

# Recreate folders
mkdir -p "${MIGRATIONS_DIR}/sqlite"
mkdir -p "${MIGRATIONS_DIR}/postgresql"

# Copy migrations for selected provider (if any exist)
if [ "$PROVIDER" = "sqlite" ]; then
    # SQLite has existing migrations - copy them
    cp -R "${MIGRATIONS_DIR}/sqlite/." "${MIGRATIONS_DIR}/"
    echo "  Copied $(ls -1 ${MIGRATIONS_DIR} | wc -l) SQLite migrations"
else
    # PostgreSQL - create from empty database
    echo "  Will create initial PostgreSQL migration from schema"
fi

echo ""
echo "Step 4: Running Prisma migrate..."
echo ""

# Check for DATABASE_URL
if [ -z "${DATABASE_URL}" ]; then
    echo "DATABASE_URL is not set. Please enter your database URL:"
    echo "Examples:"
    echo "  SQLite:  file:./dev.db"
    echo "  PostgreSQL:  postgresql://user:password@localhost:5432/excalidash"
    read -p "DATABASE_URL: " DATABASE_URL
    export DATABASE_URL
fi

cd "${PROJECT_DIR}/backend"

# Run prisma migrate
if [ "$1" = "--dev" ]; then
    MIGRATION_NAME="${2:-new_migration}"
    echo "  Running: npx prisma migrate dev --name ${MIGRATION_NAME}"
    npx prisma migrate dev --name "${MIGRATION_NAME}"
else
    echo "  Running: npx prisma migrate deploy"
    npx prisma migrate deploy
fi

echo ""
echo "Step 5: Restoring schema.prisma..."

# Restore original schema.prisma
mv "${SCHEMA_FILE}.backup" "${SCHEMA_FILE}"

echo ""
echo "Step 6: Organizing migrations..."

# Clear migrations folder
rm -rf "${MIGRATIONS_DIR}"/*

# Recreate folders
mkdir -p "${MIGRATIONS_DIR}/sqlite"
mkdir -p "${MIGRATIONS_DIR}/postgresql"

# Restore other provider (empty for postgresql, or from git for sqlite)
if [ "$PROVIDER" = "postgresql" ]; then
    # PostgreSQL folder - just the lock file
    echo 'provider = "postgresql"' > "${MIGRATIONS_DIR}/postgresql/migration_lock.toml"
    # Restore SQLite from git
    git checkout HEAD -- prisma/migrations/ 2>/dev/null || true
    mkdir -p sqlite postgresql 2>/dev/null
    mv 202* sqlite/ 2>/dev/null || true
    mv migration_lock.toml sqlite/ 2>/dev/null || true
    echo 'provider = "postgresql"' > postgresql/migration_lock.toml 2>/dev/null || true
else
    # SQLite - restore PostgreSQL (empty)
    echo 'provider = "postgresql"' > "${MIGRATIONS_DIR}/postgresql/migration_lock.toml"
fi

# Move newly generated migrations to the provider folder
if [ "$(ls -d ${MIGRATIONS_DIR}/2* 2>/dev/null)" ]; then
    for dir in "${MIGRATIONS_DIR}"/2*/; do
        if [ -d "$dir" ]; then
            cp -R "$dir" "${MIGRATIONS_DIR}/${PROVIDER}/"
            rm -rf "$dir"
        fi
    done
fi

echo ""
echo "=== Done! ==="
echo ""
echo "Generated migrations are in: ${MIGRATIONS_DIR}/${PROVIDER}/"
ls -la "${MIGRATIONS_DIR}/${PROVIDER}/"
echo ""
echo "Your schema.prisma has been restored to use env(DATABASE_PROVIDER)"
