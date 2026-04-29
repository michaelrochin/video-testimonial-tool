#!/usr/bin/env bash
# Video Testimonial Tool — Done-for-you installer
# Run during a customer screenshare to set everything up in one go.

set -e

cat <<'BANNER'
========================================================
 Video Testimonial Tool — Install
========================================================

Before continuing, the customer should have:
  1. Signed up at https://dash.cloudflare.com (free)
  2. Run "npx wrangler login" in this terminal (auth in browser)
  3. Created an R2 API Token at:
     Cloudflare → R2 → Manage R2 API Tokens → Create
     Permission: Object Read & Write (any bucket)
     They'll need the Access Key ID + Secret Access Key.

BANNER

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

# Collect inputs
echo
echo "--- Customer info ---"
read -p "Cloudflare Account ID (32-char hex from R2 dashboard): " ACCOUNT_ID
read -p "Worker name [testimonials]: " WORKER_NAME
WORKER_NAME=${WORKER_NAME:-testimonials}
read -p "R2 bucket name [testimonials]: " BUCKET_NAME
BUCKET_NAME=${BUCKET_NAME:-testimonials}
read -sp "R2 Access Key ID: " R2_ACCESS_KEY_ID; echo
read -sp "R2 Secret Access Key: " R2_SECRET_ACCESS_KEY; echo
read -p "Admin password (customer will log into the dashboard with this): " ADMIN_PASSWORD

if [[ -z "$ACCOUNT_ID" || -z "$R2_ACCESS_KEY_ID" || -z "$R2_SECRET_ACCESS_KEY" || -z "$ADMIN_PASSWORD" ]]; then
  echo "ERROR: missing required values."
  exit 1
fi

echo
echo "--- Updating wrangler.toml ---"
cp wrangler.toml wrangler.toml.bak
# Use awk for cross-platform safe in-place editing
awk -v name="$WORKER_NAME" -v acct="$ACCOUNT_ID" -v bucket="$BUCKET_NAME" '
  /^name = / { print "name = \"" name "\""; next }
  /^account_id = / { print "account_id = \"" acct "\""; next }
  /^bucket_name = / { print "bucket_name = \"" bucket "\""; next }
  { print }
' wrangler.toml.bak > wrangler.toml

echo "--- Creating R2 bucket (skipped if exists) ---"
npx wrangler r2 bucket create "$BUCKET_NAME" 2>/dev/null || echo "  (bucket already exists, continuing)"

echo "--- Applying CORS to bucket ---"
TMP_CORS=$(mktemp)
cat > "$TMP_CORS" <<EOF
{
  "rules": [
    {
      "allowed": {
        "origins": ["*"],
        "methods": ["PUT", "GET", "HEAD"],
        "headers": ["Content-Type", "Content-Length"]
      },
      "exposeHeaders": ["ETag"],
      "maxAgeSeconds": 3600
    }
  ]
}
EOF
npx wrangler r2 bucket cors set "$BUCKET_NAME" --file "$TMP_CORS" <<< "y" || true
rm -f "$TMP_CORS"

echo "--- Deploying Worker ---"
npx wrangler deploy

echo "--- Setting secrets ---"
echo "$R2_ACCESS_KEY_ID" | npx wrangler secret put R2_ACCESS_KEY_ID
echo "$R2_SECRET_ACCESS_KEY" | npx wrangler secret put R2_SECRET_ACCESS_KEY
echo "$ACCOUNT_ID" | npx wrangler secret put R2_ACCOUNT_ID
echo "$BUCKET_NAME" | npx wrangler secret put R2_BUCKET_NAME
echo "$ADMIN_PASSWORD" | npx wrangler secret put ADMIN_PASSWORD

# Detect their workers.dev subdomain by deploying — the URL prints. But we already deployed.
# Just print the canonical pattern.
echo
cat <<DONE
========================================================
 Install complete
========================================================

Your URLs (replace <subdomain> with your workers.dev subdomain):

  Dashboard:        https://${WORKER_NAME}.<subdomain>.workers.dev/config
  Recorder URL:     https://${WORKER_NAME}.<subdomain>.workers.dev/r/<client>/<funnel>
  Admin (legacy):   https://${WORKER_NAME}.<subdomain>.workers.dev/admin

Sign in to the dashboard with the admin password you just entered.
The customer can now create their first client and funnel from the
client/funnel dropdowns at the top.

Want to tighten security? Edit cors.json with the customer's specific
domain and re-run "npx wrangler r2 bucket cors set $BUCKET_NAME --file cors.json"
to replace the wildcard CORS with a domain allowlist.

DONE
