// Approves pending device pairing requests so the gateway password alone gets
// you in. OpenClaw 2026.8 retired the dangerouslyDisableDeviceAuth flag that
// did this before and added a per-browser approval step. Hyperlift apps have
// no direct shell access, so this plugin takes over that step. Pairing requests
// only exist AFTER a correct password, so this restores "password = access".
// Turn off with plugins.entries.device-autopair.enabled = false.

import { approveDevicePairing, listDevicePairing } from "openclaw/plugin-sdk/device-bootstrap";
import { formatErrorMessage } from "openclaw/plugin-sdk/error-runtime";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

const PLUGIN_ID = "device-autopair";
const INTERVAL_MS = 10_000;

function isOperatorRequest(request) {
  const roles = Array.isArray(request.roles) ? [...request.roles] : [];
  if (request.role) roles.push(request.role);
  return roles.length > 0 && roles.every((role) => role === "operator");
}

// `settled` = requestIds we won't retry (a refusal would just repeat forever
// and spam the log). Thrown errors are NOT remembered: they retry next tick.
async function approvePending(logger, settled) {
  const { pending } = await listDevicePairing();

  // Forget rows that are gone, so memory stays bounded and a request that
  // comes back later is decided (and logged) fresh.
  const pendingIds = new Set(pending.map((request) => request.requestId));
  for (const id of settled) {
    if (!pendingIds.has(id)) settled.delete(id);
  }

  for (const request of pending) {
    const { requestId, deviceId, clientId, remoteIp } = request;
    if (!requestId || settled.has(requestId)) continue;
    const scopes = Array.isArray(request.scopes) ? request.scopes : [];

    // Node enrollments (host command execution) stay manual: the auto-approve
    // lane below is only specified for operator devices, so only those go in.
    if (!isOperatorRequest(request)) {
      settled.add(requestId);
      logger.info?.(
        `${PLUGIN_ID}: left non-operator pairing request ${requestId} for manual approval (device=${deviceId} client=${clientId} ip=${remoteIp})`,
      );
      continue;
    }

    let result;
    try {
      result = await approveDevicePairing(requestId, {
        // Grant exactly what was requested: granting less locks that browser
        // out for good. The gateway itself re-checks this is a new operator
        // device; "owner" keeps it off auto-prune sweeps.
        callerScopes: scopes,
        autoApproveNewDeviceScopes: scopes,
        approvedVia: "owner",
      });
    } catch (err) {
      logger.warn?.(`${PLUGIN_ID}: approving ${requestId} failed: ${formatErrorMessage(err)}`);
      continue;
    }

    if (!result) {
      // Superseded, resolved elsewhere, or a scope upgrade the gateway won't
      // auto-approve. Log once and stop retrying so manual approvals are visible.
      settled.add(requestId);
      logger.info?.(
        `${PLUGIN_ID}: pairing request ${requestId} was not auto-approvable (already resolved, or a scope upgrade) - if it is still pending, approve it under Settings -> Devices`,
      );
      continue;
    }
    if (result.status !== "approved") {
      settled.add(requestId);
      logger.warn?.(
        `${PLUGIN_ID}: gateway refused pairing request ${requestId} (${result.reason ?? "no reason"}) device=${deviceId} client=${clientId} ip=${remoteIp}`,
      );
      continue;
    }

    logger.info?.(
      `${PLUGIN_ID}: approved device ${result.device.deviceId} client=${clientId} ip=${remoteIp} scopes=${scopes.join(",")}`,
    );
  }
}

export default definePluginEntry({
  id: PLUGIN_ID,
  name: "Device Auto-Pair",
  description: "Approve password-authenticated device pairing requests so the gateway password alone grants access.",
  register(api) {
    let timer = null;
    api.registerService({
      id: `${PLUGIN_ID}-approver`,
      start: () => {
        const settled = new Set();
        let inFlight = false;
        const tick = async () => {
          if (inFlight) return;
          inFlight = true;
          try {
            await approvePending(api.logger, settled);
          } catch (err) {
            api.logger.warn?.(`${PLUGIN_ID}: approval pass failed: ${formatErrorMessage(err)}`);
          } finally {
            inFlight = false;
          }
        };
        api.logger.info?.(`${PLUGIN_ID}: watching for pending pairing requests every ${INTERVAL_MS / 1000}s`);
        timer = setInterval(tick, INTERVAL_MS);
        timer.unref?.();
        // Hyperlift restarts the container on every env-var save; don't make
        // the first login after a restart wait out a full interval.
        void tick();
      },
      stop: () => {
        if (timer) {
          clearInterval(timer);
          timer = null;
        }
      },
    });
  },
});
