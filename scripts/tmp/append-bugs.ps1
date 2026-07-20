$path = 'D:\Smart\Claude-Code-Server\scripts\tmp\BUGS-SERIOUS-20260720.md'
$t = [IO.File]::ReadAllText($path)
$extra = @'

---

## Addendum (agents completed after first merge)

| # | Slug | Area | Conf | Problem |
|---|------|------|------|---------|
| 70 | `persian-quit-designer-win` | ux | 5 | Designer still default action=q + always-VK — Persian ض disconnects |
| 71 | `persian-quit-connect-design` | ux | 5 | connect-design.ps1 KeyChar OR Key -eq Q under Persian |
| 72 | `concurrent-watermark-server-duplication` | logging | 4 | Overlapping syncs / offset reset re-ships bytes → duplicate server log |
| 73 | `warn-sync-storm-amplifies-ram` | resource | 4 | WARN path triggers full ReadAllBytes + 3 SSH under flap |
| 74 | `hardcoded-sepidz-sudo-in-deploy-bundles` | security | 5 | Also `deploy-client-bundles.ps1` fallback `sepidz@Admin` if sudo pw missing |

Agents fully landed: [security](80b6791b), [parity](2c2976a2), [resource](332a6b53), [logging](9edf1cea), [auth](5e75497b), [mount](efccd90d), [update](9481c125), [ux](0a5a974e), [silent](0df5937f).

Updated total open serious ≈ **70+**.

'@
if ($t -notmatch 'persian-quit-designer-win') {
  [IO.File]::AppendAllText($path, $extra)
  'appended'
} else { 'already had addendum' }
