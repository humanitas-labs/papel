# ADR-003 :: Markdown resource resolution

Status: Proposed

Last updated: `2026.08.31`

> Paper resolves local resources from the Markdown file that names them. It does not infer a project, expand shell syntax, or fetch remote media automatically.

---

## 1. Decision

The parent directory of a saved Markdown document is the base for every relative resource path. The same resolver governs links, images, and future embedded media.

| Destination | Resolution |
|---|---|
| `image.png` or `./image.png` | Beside the Markdown file |
| `../assets/image.png` | Relative to the Markdown file, with `.` and `..` standardized |
| `/Users/me/image.png` | Absolute filesystem path |
| `image%20one.png` | Percent-decoded local filename |
| `https://example.com/image.png` | Remote resource; not fetched automatically |
| `~/image.png` | Literal relative path; `~` is not expanded |

An unsaved document has no filesystem base. Its relative resources remain unresolved until the document is saved. Missing, unreadable, unsupported, and remote embedded resources show their alt-text fallback. A relative link in an unsaved document does not fall back to the home directory or process working directory.

Save As or any other document URL change establishes a new base and causes relative resources to resolve again. Symlinks and paths outside the document directory follow ordinary filesystem behavior; Paper imposes no project or repository boundary.

Resolution affects presentation only. Paper never rewrites, normalizes, or replaces the destination stored in the Markdown source.

## 2. Rationale

Markdown files must remain portable independently of Paper. Resolving from the containing file matches ordinary document behavior and keeps a document tree valid when it is moved as a unit. Paper has no project or workspace model, so repository-root semantics would introduce hidden state that cannot be inferred reliably from an ordinary file.

Automatic remote-media loading would make a network request merely by opening a document. Paper therefore leaves remote media unloaded unless a later decision introduces an explicit user-controlled policy. Ordinary remote links may still open when the user activates them.

## 3. Alternatives rejected

- Resolving from the process working directory would make behavior depend on how Paper was launched.
- Falling back to the home directory for unsaved documents would turn an unresolved path into an unrelated local path.
- Searching upward for a Git repository would make the same file behave differently inside and outside a checkout.
- Treating a leading `/` as a repository-relative path would require a workspace concept Paper does not have.
- Expanding `~` would embed shell-specific behavior into otherwise portable Markdown.
- Fetching remote media automatically would violate the expectation that opening a local document is a local operation.

## 4. Consequences

- A repository-root README can render `docs/assets/paper.png` because the path is relative to that README.
- Documents with relative media must be saved before the media can render.
- Moving a document without moving its relative resources may break those references, as it does in other file-based tools.
- GitHub- or Zed-specific workspace-root paths beginning with `/` may resolve differently in Paper; portable documents should use file-relative paths.
- Resource resolution should be implemented once and shared by links, images, and future media.

## 5. When to revisit

Reconsider remote loading if Paper gains an explicit permission or trust model. Reconsider workspace-root paths only if Paper deliberately adopts a project abstraction. Reconsider filesystem access if application sandboxing requires security-scoped document relationships.
