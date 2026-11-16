-- Persistent license storage for ERI Login Admin.
-- Run with: npx wrangler d1 migrations apply ERI_KEYS --remote
CREATE TABLE IF NOT EXISTS device_keys (
  id TEXT PRIMARY KEY,
  key_value TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK (platform IN ('ios','android')),
  device_id TEXT,
  locked INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_key_per_device
  ON device_keys(platform, device_id)
  WHERE device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_keys_platform_created
  ON device_keys(platform, created_at DESC);
