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
  ;; *only* that. Other failures (bad device, bad address, EPERM) exit 1
  ;; and must still fail the update so s6 replays it: `|| true` swallowed
  ;; those too, leaving the old prefix on the interface while the snapshot
  ;; had already forgotten it.
  (each [_ p (ipairs (deletions addresses new-addresses))]
    (exec
     (.. "ip address del " p.address "1/" p.len " dev " wan-device
         " || test $? -eq 2")))
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

;; One reconciliation step. Its return value is the baseline for the next
;; event, so it has to be the new address set - not write-snapshot's result
;; (os.rename returns true). Using the latter as the accumulator made the
;; second event call pairs(true) and kill the service.
(fn reconcile [device addresses new exec snapshot]
  ;; snapshot after updating, not before: update is idempotent, so a
  ;; crash between the two replays it on the next run, whereas the
  ;; reverse order would forget the old prefix and leave it on the LAN
  (update-prefixes device addresses new exec)
  (write-snapshot snapshot new)
  new)

(fn run []
  (let [[state-directory lan-device snapshot-directory] arg
        dir (svc.open state-directory)
        snapshot (.. (or snapshot-directory state-directory) "/pd-snapshot")
        known (read-snapshot snapshot)
        initial (dir:output "prefix")]
    (when initial
      (reconcile lan-device known initial system snapshot))
    (accumulate [addresses (or initial known)
                 v (dir:events)]
      (let [new (v:output "prefix")]
        (if new
            (reconcile lan-device addresses new system snapshot)
            ;; a failed read is not "all prefixes were withdrawn": keep
            ;; the baseline and wait for the next event
            addresses)))))

{ : update-prefixes : deletions : reconcile : read-snapshot : write-snapshot : run }
