# Disk Cleaner — Product Spec

v1 helps a Mac user see what is using space on a local disk and reclaim it from junk and large files. A scan only lists files. Deletion happens after the user reviews a preview and confirms.

## Who it is for

A person on their own Mac whose disk is filling up. They can read a folder list and a file size. They are not asked to type paths or use Terminal.

## v1 includes

- **Space scan.** Break a chosen disk down by folder, by app, and by file size.
- **Junk cleanup.** Clear user caches, system caches the user is allowed to remove, logs, browser cache, the Trash, and old downloads.
- **Large-file finder.** List the biggest files and the biggest folders so the user can choose what to keep.

## Later

Duplicate finder, app uninstaller, developer leftovers (Xcode DerivedData, `node_modules`, Docker images, simulators), and privacy wipe (history, cookies, recent items).

## Safety

These rules apply to every feature.

- A scan never deletes, moves, or rewrites a file.
- The user sees the items, the count, and the total size, then confirms, before anything is removed.
- Removable junk and large files go to the Trash. The user can put them back from the Trash.
- Emptying the Trash is a separate action. Its confirm copy states that the delete is permanent.
- The app never offers these locations for delete: `/System`, `/usr`, `/bin`, `/sbin`, `/private/var` outside `/private/var/log` and `/private/var/folders`, the home folder itself, and the app’s own bundle.
- Items the scan cannot read are skipped and counted. The scan continues.
- Sizes in the app are logical sizes (the size a file reports). The summary also shows the volume’s used, free, and purgeable space from macOS, because a file scan and the Storage pane will differ by purgeable space, snapshots, and folders the app could not read.

## Shared scan

- The startup disk is selected by default. The user can switch to another local mounted volume, or to their home folder.
- Network volumes and disk images are out of the picker.
- The user can cancel. Canceled results stay on screen and are labeled **Partial scan**.
- A rescan replaces the current results.
- Progress shows the folder currently being read and the number of items scanned.
- Each file is counted once. The scan does not follow a symbolic link into a folder it has already walked.
- When Full Disk Access is missing, the app scans what it can read and shows a banner: how many locations were skipped, and a button that opens the Full Disk Access settings pane.

## 1. Space scan

The user opens the app and sees where space went, then drills in.

### Summary

For the selected volume, show:

- Name and capacity
- Used, free, and purgeable
- Amount this scan was able to measure
- Amount skipped for lack of permission

### By folder

- Start at the selected root (`/` for a volume, or the home folder).
- Show each child folder and file with its total logical size, sorted largest first.
- Expanding a folder loads its children. Sizes include nested contents.
- A row shows name, size, and share of the scanned total (for example, 12.4 GB, 18%).

### By app

- List application bundles in `/Applications`, `/System/Applications`, and `~/Applications`.
- Size is the bundle only. Support files, containers, and caches stay in the folder view.
- Columns: app name, size, location.
- Selecting an app reveals it in Finder.

### By file size

Group scanned files into these buckets:

| Bucket | Range |
| --- | --- |
| Small | Under 10 MB |
| Medium | 10 MB up to 100 MB |
| Large | 100 MB up to 1 GB |
| Huge | 1 GB and up |

Each bucket shows a file count and a total size. Small files stay as a total. Opening Medium, Large, or Huge opens the large-file finder filtered to that range.

### Done when

- After a completed scan of the home folder, the user can name the largest top-level folder, the largest app bundle, and which size bucket holds the most bytes.
- A missing Full Disk Access grant still produces a partial result and the banner, and the app stays usable.

## 2. Junk cleanup

Junk is a fixed set of categories. The user reviews each category and chooses what to remove.

### Categories

| Category | What is included | Default |
| --- | --- | --- |
| User caches | Files inside `~/Library/Caches` | Selected |
| System caches | Files inside `/Library/Caches` that the user can delete | Selected |
| Logs | Files inside `~/Library/Logs` and `/Library/Logs` last modified at least 24 hours ago | Selected |
| Browser cache | Cache directories for Safari, Chrome, Firefox, Edge, Brave, and Arc, when that browser is installed | Selected |
| Trash | Contents of `~/.Trash` | Unselected |
| Old downloads | Files in `~/Downloads` last modified at least 30 days ago | Unselected |

- The cache and log folders themselves stay. Only their contents are removable.
- Logs modified in the last 24 hours stay, so a recent crash log remains.
- Browser cleanup removes cache files only. Bookmarks, history, cookies, passwords, and extensions stay.
- If a browser is running, its cache is listed, unchecked, and labeled **Quit the browser to clean this**.
- A download is old when its modified date is at least 30 days ago. The user can change that age to 7, 30, 90, or a custom number of days. A folder in Downloads is old when every file inside it meets that age. Partial downloads (`.download`, `.crdownload`, `.part`) stay.
- Trash is unchecked because emptying it is permanent. The confirm sheet says so.

### Review

- Each category shows item count and total size.
- Expanding a category lists the items (name, path, size).
- The user can uncheck a category or a single item.
- The footer shows the selected count and the total size, and a **Move to Trash** button.
- When the only selected category is Trash, the button reads **Empty Trash**.

### Done when

- The user can clear selected caches and logs, then find those items in the Trash.
- With Chrome running, Chrome’s cache stays unchecked and is not removed.
- Empty Trash asks for a permanent-delete confirmation and removes the listed Trash items only after that confirmation.
- A file modified 29 days ago stays in Downloads when the age is 30 days. A file modified 30 days ago is listed.

## 3. Large-file finder

The finder uses the same scan as the space view. It answers “what are the biggest things, and do I still want them?”

### Files

- Default list: files of at least 100 MB, largest first.
- The user can set the minimum to 50 MB, 100 MB, 500 MB, 1 GB, or a custom size.
- Columns: name, path, size, kind, date modified.
- A name search filters the list.

### Folders

- Show the 50 largest folders in the scan, largest first.
- Minimum size matches the file threshold (default 100 MB).
- Columns: folder name, path, total size.
- Expanding a folder shows its children from the scan.

### Actions

- **Reveal in Finder** shows the file or folder.
- **Move to Trash** is available for items outside the protected locations listed under Safety. The preview lists each selected path and the total size.

### Done when

- On a scan that contains a 2 GB file and a 40 MB file, only the 2 GB file appears at the default 100 MB minimum.
- Lowering the minimum to 50 MB adds the 40 MB file.
- The folder list shows 50 folders at most, sorted largest first.
- Moving a listed file to the Trash removes it from the list and reduces the totals by that file’s size.

## Delete preview

Used by junk cleanup and the large-file finder.

- The sheet lists each selected item’s name, path, and size, plus the combined count and size.
- **Move to Trash** moves the items and closes the sheet. Failures stay in the list with the reason on that row. Succeeded items leave the list, and the totals drop by their sizes.
- **Empty Trash** uses the sheet title **Delete permanently** and the button **Delete Permanently**. The body states that the items cannot be restored from the Trash.
- Cancel closes the sheet and leaves the disk unchanged.

## Layout

One window, three sections:

1. **Space** — summary, then Folder, App, and File size.
2. **Junk** — the six categories and the remove action.
3. **Large files** — Files and Folders, the size minimum, and search.

The volume picker and **Scan** sit at the top and apply to all three sections. A completed scan fills all three. Junk categories that live outside the selected root still scan their own paths when the user opens Junk (home-folder caches, browsers, Trash, and Downloads), and the section says which user those paths belong to.

## Architecture

Locked for v1. One SwiftUI window reads an in-memory scan snapshot. A separate delete path is the only code that changes the disk. The app stays in the user session, uses Full Disk Access when the user has granted it, and does not install a root helper or ask for an admin password.

### Snapshot

Space, Junk, and Large files are three views of one snapshot. The views do not walk the disk.

- A finished scan replaces the snapshot.
- Cancel keeps the partial snapshot and labels it **Partial scan**.
- The snapshot is immutable. The UI swaps in a new value when a scan or a delete finishes.
- v1 keeps the snapshot in memory. Closing the app drops it.

### Scan

One cancellable scan fills the snapshot. It has two parts.

- **Tree walk.** Sizes the selected root for folders, app bundles, size buckets, and large files. Sizes are logical. Each file is counted once. The walk does not follow a symlink or firmlink onto a volume it is already counting.
- **Junk catalog.** A fixed table of known folders: user caches, system caches, logs, browser cache, Trash, and Downloads. Rules cover age and whether a browser is open. The catalog runs for the current user even when the tree root is the home folder. Junk is not inferred from filenames.

Missing Full Disk Access still returns a partial snapshot and a skipped count.

### Delete

Delete accepts only the paths the user confirmed in the preview.

- Caches, logs, browser cache, old downloads, and large files move to the Trash.
- Empty Trash permanently removes the listed Trash items.
- Protected prefixes are refused after symlinks are resolved: `/System`, `/usr`, `/bin`, `/sbin`, `/private/var` outside `/private/var/log` and `/private/var/folders`, the home folder itself, and the app’s own bundle.
- Each path returns success or a reason. Successes leave the snapshot. Failures stay, with the reason on the row.

The walker never deletes. The junk catalog never deletes. Only the delete path writes to the disk.

## Vertical slices

Approved build order. Each slice is clickable on its own. Tests for the walker or delete path ship inside the slice that adds them, run against a temporary folder.

1. **Home folder.** The window, Scan, and an in-memory snapshot of the home folder. Folders show logical size and share, and they expand. Progress, cancel, and rescan work. This slice is read-only.
2. **Startup disk.** The picker adds Macintosh HD. The summary shows used, free, purgeable, scanned, and skipped. The walk stays on one volume, so the Data volume is counted once. A missing Full Disk Access grant shows the skipped count and opens that settings pane.
3. **Apps and size.** App bundles from `/Applications`, `/System/Applications`, and `~/Applications`, with Reveal in Finder. Four buckets: under 10 MB, 10 MB–100 MB, 100 MB–1 GB, and 1 GB and up. Small stays a total. Medium, Large, and Huge open a file list from the same snapshot. This slice is read-only.
4. **Large files.** The first slice that writes to the disk. The minimum size defaults to 100 MB, with 50 MB, 500 MB, and 1 GB. Name search, the 50 largest folders, Reveal, and a preview that moves the selection to the Trash. Protected paths are refused and stay on the row with a reason. Totals drop for successes.
5. **Junk.** The six categories for the current user, with counts, sizes, and checkboxes. Logs are limited to files last modified at least 24 hours ago. A running browser stays unchecked. Downloads default to 30 days, with 7, 90, and custom. Partial downloads stay. Selected caches, logs, browser cache, and old downloads go to the Trash through the slice 4 delete path.
6. **Empty Trash.** Trash stays unchecked. When it is the only selection, the button says Empty Trash. The sheet says the items cannot be restored. Cancel leaves the disk unchanged. Confirm permanently removes only the listed Trash items.

Slice 2 is where a startup-disk walk can double-count the Data volume. Slice 4 is the first time the app writes. Those two get the closest review.

## Acceptance for v1

- Scan the startup disk or the home folder, cancel, and rescan, without deleting anything during the scan.
- See folder, app, and file-size breakdowns from that scan.
- Review the six junk categories, change the downloads age, and move a selected subset to the Trash.
- Empty the Trash only after the permanent-delete confirmation.
- Find files and folders at or above a chosen size, reveal one in Finder, and move one to the Trash.
- With Full Disk Access off, show a partial scan, the skipped count, and a way to open the settings pane.
