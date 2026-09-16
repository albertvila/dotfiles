// Disables pi-mcp-adapter's MCP-UI viewer windows: Atlassian's Jira/Confluence
// widgets never finish loading in the sandbox and pop blank browser windows.
// Delete this file to get the widgets back.
process.env.MCP_UI_VIEWER ??= "none";

export default function () {}
