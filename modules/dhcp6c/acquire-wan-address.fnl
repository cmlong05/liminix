(local { : system } (require :anoia))
(local svc (require :anoia.svc))

(fn deletions [old-addresses new-addresses]
  (let [deleted {}]
    (each [n address (pairs old-addresses)]
      (let [now (. new-addresses n)]
        (if (or (not now) (not (= now.len address.len)))
            (table.insert deleted address))))
    deleted))

(fn update-addresses [wan-device addresses new-addresses exec]
  ;; The address may already be gone - its lifetime ran out, or the
  ;; uplink came back with a different one - and `ip` exits 2 saying so.
  ;; That is the state we wanted. Tolerate *only* that exit code: other
  ;; failures (bad device, bad address, EPERM) exit 1 and must still fail
  ;; the update so s6 replays it. `|| true` swallowed those too, leaving
  ;; the old address behind while the snapshot had already forgotten it.
  (each [_ p (ipairs (deletions addresses new-addresses))]
    (exec
     (.. "ip address del " p.address "/" p.len " dev " wan-device
         " || test $? -eq 2")))
  (each [_ p (pairs new-addresses)]
    (exec
     (.. "ip address change " p.address "/" p.len
         " dev " wan-device
         " valid_lft " p.valid
         " preferred_lft " p.preferred
         )))
  new-addresses)

;; dhcp6c empties its outputs whenever it restarts, and this service's
;; in-memory baseline dies with the process. Without a record of our own,
;; addresses left on the WAN interface are never deleted and linger until
;; their valid lifetime expires. Same reconciliation problem as the
;; delegated-prefix service, so use the same snapshot mechanism.

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

;; One reconciliation step; returns the baseline for the next event.
(fn reconcile [device addresses new exec snapshot]
  (update-addresses device addresses new exec)
  (write-snapshot snapshot new)
  new)

(fn run []
  (let [[state-directory wan-device snapshot-directory] arg
        dir (svc.open state-directory)
        snapshot (.. (or snapshot-directory state-directory) "/addr-snapshot")
        known (read-snapshot snapshot)
        initial (dir:output "address")]
    (when initial
      (reconcile wan-device known initial system snapshot))
    (accumulate [addresses (or initial known)
                 v (dir:events)]
      (let [new (v:output "address")]
        (if new
            (reconcile wan-device addresses new system snapshot)
            ;; a failed read is not "all addresses were withdrawn": keep
            ;; the baseline and wait for the next event
            addresses)))))

{ : update-addresses : deletions : reconcile : read-snapshot : write-snapshot : run }
