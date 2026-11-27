export default {
  docs: [
    "index",
    "wrapper",
    {
      type: "category",
      label: "Modes",
      link: { type: "doc", id: "modes" },
      items: [
        "modes/interactive",
        "modes/programmatic",
        "modes/api",
        "modes/mcp",
        "modes/telegram",
        "modes/cron",
      ],
    },
    "environment-variables",
    "customization",
    "github-action",
    "agent-integrations",
    "architecture",
    "troubleshooting",
    "upgrading",
    "development",
  ],
};
