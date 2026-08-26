# Evidence — Kiro Pix4K test provider

- Date: 2026-08-27
- Scope: owner-supplied free test credential in ignored `setting.json`

## Sanitized observation

- Base endpoint `https://kiro.pix4k.com/v1` answered the authenticated model
  catalog request with HTTP 200.
- The advertised catalog included exact model ID `claude-opus-4.7`; the route
  uses that ID with protocol `openai_chat_completions`.
- The pasted text had visually joined “quota” and “Base Url”. The literal path
  `/quotaBase` returned HTTP 404 for GET, POST and OPTIONS. `/quota` returned an
  HTML quota page and its public JavaScript asset, not a stable JSON quota API.
- The owner-authorized non-sensitive completion probe initially received HTTP
  429, then one bounded retry was accepted with a successful 2xx response. This
  proves the configured chat-completions path can reach inference, while the
  first result also shows that the free relay may throttle transiently.
- Credential values, authentication headers and provider response bodies were
  not printed or copied to tracked evidence.

## Applied behavior

- Exactly one ignored provider/profile named `Kiro Pix4K Test` was added to
  `setting.json`; the credential stays only there and in CCR's ignored database
  after the owner launches/synchronizes the route.
- Dashboard may open the provider's `/quota` page through an allowlisted server
  action only after validating HTTPS, same API host and absence of URL
  credentials. It never appends the API key to the URL.
- The general schema now documents optional `quota_page_url`; this is a link to
  a provider-owned page, not a claim that local proxy counters equal provider
  subscription quota.

## Remaining owner proof

Select the Kiro route in the dashboard and send one short non-sensitive request
through Claude Code itself. The direct API path is proved, but the complete
Claude -> CCR -> relay tool loop remains an owner-visible live check. The relay
is a third-party endpoint, so do not send private source/data until the owner
accepts its privacy, retention and terms.
