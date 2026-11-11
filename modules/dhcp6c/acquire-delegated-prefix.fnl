(local { : system } (require :anoia))
(local svc (require :anoia.svc))

(fn deletions [old-addresses new-addresses]
  (let [deleted {}]
    (each [n address (pairs old-addresses)]
      (let [now (. new-addresses n)]
        (if (or (not now) (not (= now.len address.len)))
            (table.insert deleted address))))
    deleted))

(fn update-prefixes [wan-device addresses new-addresses exec]
  ;; `del` is not idempotent the way `change` is: the address is runtime
  ;; state, so after a reboot - or once its lifetime runs out - it is not
  ;; there to delete, and `ip` exits 2 with "address not found". Tolerate
  ;; that, because the snapshot below is written only after the update:
  ;; an error here leaves the stale prefix on record, the service is
  ;; restarted, and every run repeats the same failing delete.
  (each [_ p (ipairs (deletions addresses new-addresses))]
    (exec
     (.. "ip address del " p.address "1/" p.len " dev " wan-device
         " || true")))
  (each [_ p (pairs new-addresses)]
    (exec
     (.. "ip address change " p.address "1/" p.len
         " dev " wan-device
         " valid_lft " p.valid
         " preferred_lft " p.preferred
         )))
  new-addresses)

;; The client's state directory is emptied whenever dhcp6c restarts, so a
;; prefix we put on the LAN outlives any knowledge of it: the next client
;; asks for a prefix, may well be given a different one, and nothing
;; removes the old address - it stays until its valid lifetime (three
;; days) expires. Keep our own record of the last set and start from it,
;; so that a restart reconciles instead of accumulating.

(fn read-snapshot [pathname]
  (match (io.open pathname :r)
    f (let [snapshot {}]
        (each [line (f:lines)]
          (let [(key address len) (string.match line "(%S+) (%S+)/(%d+)")]
            (when key
              (tset snapshot key { : address : len }))))
        (f:close)
        snapshot)
    nil {}))

(fn write-snapshot [pathname snapshot]
  (match (io.open (.. pathname ".new") :w)
    f (do
        (each [key address (pairs snapshot)]
          (f:write key " " address.address "/" address.len "\n"))
        (f:close)
        (os.rename (.. pathname ".new") pathname))
    nil nil))

(fn run []
  (let [[state-directory lan-device snapshot-directory] arg
        dir (svc.open state-directory)
        snapshot (.. (or snapshot-directory state-directory) "/pd-snapshot")
        known (read-snapshot snapshot)
        current (or (dir:output "prefix") [])]
    ;; snapshot after updating, not before: update is idempotent, so a
    ;; crash between the two replays it on the next run, whereas the
    ;; reverse order would forget the old prefix and leave it on the LAN
    (update-prefixes lan-device known current system)
    (write-snapshot snapshot current)
    (accumulate [addresses current
                 v (dir:events)]
      (let [new (or (v:output "prefix") [])]
        (update-prefixes lan-device addresses new system)
        (write-snapshot snapshot new)))))

{ : changes : run }
