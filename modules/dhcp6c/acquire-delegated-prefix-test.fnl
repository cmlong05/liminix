(local subject (require :acquire-delegated-prefix))
(import-macros { : expect= } :anoia.assert)

;; nix-shell --run "cd modules/dhcp6c && fennelrepl acquire-delegated-prefix-test.fnl"

(local p1
       { "prefix/2001-db8-aaaa-" { :address "2001:db8:aaaa::"
                                   :len "56"
                                   :preferred "3600"
                                   :valid "7200" } })

(local p2
       { "prefix/2001-db8-bbbb-" { :address "2001:db8:bbbb::"
                                   :len "56"
                                   :preferred "3600"
                                   :valid "7200" } })

(local p148
       { "prefix/2001-db8-aaaa-" { :address "2001:db8:aaaa::"
                                   :len "48"
                                   :preferred "3600"
                                   :valid "7200" } })

(fn old-prefix-is-deleted []
  (expect= (. (subject.deletions p1 p2) 1)
           (. p1 "prefix/2001-db8-aaaa-")))

(fn changed-length-is-deleted []
  ;; "ip address change" silently ignores a changed prefix length, so the
  ;; old address has to be removed before reinstating it
  (expect= (. (subject.deletions p1 p148) 1)
           (. p1 "prefix/2001-db8-aaaa-")))

(fn two-events-keep-the-baseline []
  ;; Reproduce run()'s event loop: the first step's return value must be a
  ;; usable address set for the second step. Before the fix the accumulator
  ;; was overwritten by write-snapshot's return value (true), so the second
  ;; event called pairs(true) and killed the service.
  (let [snapshot (os.tmpname)
        cmds []]
    (let [baseline
          (subject.reconcile "lan0" p1 p1
                             (fn [c] (table.insert cmds c)) snapshot)]
      (expect= baseline p1)
      (subject.reconcile "lan0" baseline p2
                         (fn [c] (table.insert cmds c)) snapshot))
    (expect=
     cmds
     [ "ip address change 2001:db8:aaaa::1/56 dev lan0 valid_lft 7200 preferred_lft 3600"
       "ip address del 2001:db8:aaaa::1/56 dev lan0 || test $? -eq 2"
       "ip address change 2001:db8:bbbb::1/56 dev lan0 valid_lft 7200 preferred_lft 3600" ])
    (os.remove snapshot)))

(fn snapshot-reconciles-after-restart []
  ;; dhcp6c empties its outputs on restart and the in-memory baseline is
  ;; gone; the snapshot must let us delete the prefix left on the LAN
  (let [snapshot (os.tmpname)]
    (subject.write-snapshot snapshot p1)
    (let [cmds []
          known (subject.read-snapshot snapshot)]
      (subject.reconcile "lan0" known p2
                         (fn [c] (table.insert cmds c)) snapshot)
      (expect= (. cmds 1)
               "ip address del 2001:db8:aaaa::1/56 dev lan0 || test $? -eq 2"))
    (os.remove snapshot)))

(old-prefix-is-deleted)
(changed-length-is-deleted)
(two-events-keep-the-baseline)
(snapshot-reconciles-after-restart)

(print "OK")
