#!/bin/bash
# scan-summary.sh - Generate human-friendly summary from Clair JSON scan results
# Requires: jq
set -euo pipefail

SCAN_DIR="${1:-scan-results}"

if ! command -v jq >/dev/null 2>&1; then
	echo "ERROR: jq is required for scan-summary but is not installed."
	echo "Install: sudo dnf install jq"
	exit 1
fi

if [ ! -d "${SCAN_DIR}" ]; then
	echo "ERROR: Scan results directory not found: ${SCAN_DIR}"
	exit 1
fi

JSON_FILES=("${SCAN_DIR}"/*.json)
if [ ! -f "${JSON_FILES[0]}" ]; then
	echo "ERROR: No JSON scan result files found in ${SCAN_DIR}/"
	exit 1
fi

echo "=== Vulnerability Scan Summary ==="
echo "Generated: $(date +%Y-%m-%d)"
echo ""

# Track all vulns across images for cross-image dedup
ALL_VULNS_TMPFILE=$(mktemp)
trap 'rm -f "${ALL_VULNS_TMPFILE}"' EXIT

for json_file in "${JSON_FILES[@]}"; do
	[ -f "${json_file}" ] || continue

	# Skip files that contain error responses instead of scan results
	if jq -e '.code' "${json_file}" >/dev/null 2>&1; then
		echo "--- $(basename "${json_file}" .json) ---"
		echo "  SKIPPED: File contains error response: $(jq -r '.message' "${json_file}")"
		echo ""
		continue
	fi

	IMAGE_NAME=$(basename "${json_file}" .json)

	# Extract vulnerabilities into a normalized format
	# clairctl JSON structure: .vulnerabilities is an object keyed by vuln ID
	# Each entry has .name, .normalized_severity, .package.name, .package.version, .fixed_in_version
	VULN_DATA=$(jq -r '
		[.vulnerabilities // {} | to_entries[] | {
			id: .key,
			name: .value.name,
			severity: (.value.normalized_severity // "Unknown"),
			package: .value.package.name,
			version: .value.package.version,
			fixed: (.value.fixed_in_version // "no fix available")
		}] | unique_by(.id)
	' "${json_file}" 2>/dev/null || echo "[]")

	# If the JSON structure is different (array of vulns), try alternative parsing
	if [ "${VULN_DATA}" = "[]" ]; then
		VULN_DATA=$(jq -r '
			[.. | objects | select(.name? and .package?) |  {
				id: .name,
				name: .name,
				severity: (.normalized_severity // "Unknown"),
				package: .package.name,
				version: .package.version,
				fixed: (.fixed_in_version // "no fix available")
			}] | unique_by(.id)
		' "${json_file}" 2>/dev/null || echo "[]")
	fi

	TOTAL=$(echo "${VULN_DATA}" | jq 'length')
	CRITICAL=$(echo "${VULN_DATA}" | jq '[.[] | select(.severity == "Critical")] | length')
	HIGH=$(echo "${VULN_DATA}" | jq '[.[] | select(.severity == "High")] | length')
	MEDIUM=$(echo "${VULN_DATA}" | jq '[.[] | select(.severity == "Medium")] | length')
	LOW=$(echo "${VULN_DATA}" | jq '[.[] | select(.severity == "Low")] | length')
	UNKNOWN=$(echo "${VULN_DATA}" | jq '[.[] | select(.severity == "Unknown" or .severity == "Negligible")] | length')
	FIXABLE=$(echo "${VULN_DATA}" | jq '[.[] | select(.fixed != "no fix available" and .fixed != "")] | length')

	echo "--- ${IMAGE_NAME} (${TOTAL} unique vulns) ---"
	echo "  Critical: ${CRITICAL}  High: ${HIGH}  Medium: ${MEDIUM}  Low: ${LOW}  Unknown: ${UNKNOWN}"
	echo "  Fixable: ${FIXABLE}/${TOTAL}"
	echo ""

	# Print vulns grouped by severity then package
	for SEVERITY in Critical High Medium Low Unknown; do
		SEV_FILTER="${SEVERITY}"
		if [ "${SEVERITY}" = "Unknown" ]; then
			SEV_FILTER_JQ='select(.severity == "Unknown" or .severity == "Negligible")'
		else
			SEV_FILTER_JQ="select(.severity == \"${SEVERITY}\")"
		fi

		SEV_COUNT=$(echo "${VULN_DATA}" | jq "[.[] | ${SEV_FILTER_JQ}] | length")
		if [ "${SEV_COUNT}" -eq 0 ]; then
			continue
		fi

		echo "  ${SEVERITY^^}:"

		# Group by package, sorted by number of vulns descending
		echo "${VULN_DATA}" | jq -r "
			[.[] | ${SEV_FILTER_JQ}]
			| group_by(.package)
			| sort_by(-length)
			| .[]
			| {
				package: .[0].package,
				version: .[0].version,
				fixed: ([.[] | .fixed] | unique | join(\", \")),
				ids: [.[] | .id] | join(\", \")
			}
			| \"    \(.package) \(.version) -> \(.fixed)\n      \(.ids)\"
		"
		echo ""
	done

	# Append to cross-image tracking
	echo "${VULN_DATA}" >> "${ALL_VULNS_TMPFILE}"
done

# Cross-image deduplicated summary
echo "=== Cross-Image Summary (deduplicated) ==="

CROSS_TOTAL=$(jq -s 'flatten | unique_by(.id) | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")
CROSS_CRITICAL=$(jq -s 'flatten | unique_by(.id) | [.[] | select(.severity == "Critical")] | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")
CROSS_HIGH=$(jq -s 'flatten | unique_by(.id) | [.[] | select(.severity == "High")] | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")
CROSS_MEDIUM=$(jq -s 'flatten | unique_by(.id) | [.[] | select(.severity == "Medium")] | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")
CROSS_LOW=$(jq -s 'flatten | unique_by(.id) | [.[] | select(.severity == "Low")] | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")
CROSS_UNKNOWN=$(jq -s 'flatten | unique_by(.id) | [.[] | select(.severity == "Unknown" or .severity == "Negligible")] | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")
CROSS_FIXABLE=$(jq -s 'flatten | unique_by(.id) | [.[] | select(.fixed != "no fix available" and .fixed != "")] | length' "${ALL_VULNS_TMPFILE}" 2>/dev/null || echo "0")

echo "Total unique vulnerabilities: ${CROSS_TOTAL}"
echo "  Critical: ${CROSS_CRITICAL}  High: ${CROSS_HIGH}  Medium: ${CROSS_MEDIUM}  Low: ${CROSS_LOW}  Unknown: ${CROSS_UNKNOWN}"
echo "Fixable: ${CROSS_FIXABLE}/${CROSS_TOTAL}"
