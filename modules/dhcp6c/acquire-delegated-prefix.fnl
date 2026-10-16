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
  (each [_ p (ipairs (deletions addresses new-addresses))]
    (exec
     (.. "ip address del " p.address "1/" p.len " dev " wan-device)))
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
    (write-snapshot snapshot current)
    (update-prefixes lan-device known current system)
    (accumulate [addresses current
                 v (dir:events)]
      (let [new (or (v:output "prefix") [])]
        (write-snapshot snapshot new)
        (update-prefixes lan-device addresses new system)))))

{ : changes : run }
