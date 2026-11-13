(local subject (require :acquire-wan-address))
(import-macros { : expect= } :anoia.assert)
(local { : merge : dup } (require :anoia))

;; nix-shell --run "cd modules/dhcp6c && fennelrepl acquire-wan-address-test.fnl"

(local a1
       {
        "2001-ab-cd-ef" {
                      	 :address "2001:ab:cd:ef"
                         :len "64"
                         :preferred "3600"
                         :valid "7200"
                         }
        }
       )

(local a156
       {
        "2001-ab-cd-ef" {
                      	 :address "2001:ab:cd:ef"
                         :len "56"
                         :preferred "3600"
                         :valid "7200"
                         }
        }
       )

(local a2
       {
        "2001-0-1-2-3" {
                        :address "2001:0:1:2:3"
                        :len "64"
                        :preferred "3600"
                        :valid "7200"
                        }
        }
       )

(local a21
       {
        "2001-0-1-2-3" {
                        :address "2001:0:1:2:3"
                        :len "64"
                        :preferred "1800"
                        :valid "5400"
                        }
        }
       )

(fn first-address []
  (let [deleted
        (subject.deletions
         { }
         a1
         )]
    (expect= deleted [])))

(fn second-address []
  (let [del
        (subject.deletions
         a1
         (merge (dup a1) a2)
         )]
    (expect= del [])))

(fn old-address-is-deleted []
  (let [del
        (subject.deletions
         (merge (dup a1) a2)
         a1
         )]
    (expect= (. del 1) (. a2 "2001-0-1-2-3"))
    ))

(fn changed-lifetime-not-deleted []
  (let [del
        (subject.deletions
         (merge (dup a1) a2)
         (merge (dup a1) a21)
         )]
    ;; when an address lifetime changes, "ip address change"
    ;; will update that so it need not (should not) be deleted
    (expect= del [])))

(fn changed-prefix-is-deleted []
  (let [del
        (subject.deletions a1 a156)]
    ;; when an address prefix changes, "ip address change"
    ;; ignores that cjhange, so we have to remove the
    ;; address before reinstating it
    (expect= del [(. a1 "2001-ab-cd-ef")])))

(fn reconcile-returns-the-new-baseline []
  ;; the value handed to the next event must be the new address set, not
  ;; write-snapshot's result (os.rename returns true) - using true as the
  ;; baseline makes the following event call pairs(true) and die
  (let [snapshot (os.tmpname)
        cmds []
        baseline
        (subject.reconcile
         "ppp0" (merge (dup a1) a2) a1
         (fn [c] (table.insert cmds c)) snapshot)]
    (expect= baseline a1)
    (let [cmds2 []]
      (subject.reconcile
       "ppp0" baseline a2
       (fn [c] (table.insert cmds2 c)) snapshot)
      (expect= (. cmds2 1)
               "ip address del 2001:ab:cd:ef/64 dev ppp0 || test $? -eq 2"))
    (os.remove snapshot)))

(fn snapshot-entries-can-be-a-baseline []
  ;; read-snapshot only restores address/len; deletions must work with
  ;; just those two fields, so a restart can reconcile with the kernel
  (let [snapshot (os.tmpname)]
    (subject.write-snapshot snapshot (merge (dup a1) a2))
    (let [del (subject.deletions (subject.read-snapshot snapshot) a1)]
      (expect= (# del) 1)
      (expect= (. (. del 1) "address") "2001:0:1:2:3")
      (expect= (. (. del 1) "len") "64"))
    (os.remove snapshot)))

(first-address)
(second-address)
(old-address-is-deleted)
(changed-lifetime-not-deleted)
(changed-prefix-is-deleted)
(reconcile-returns-the-new-baseline)
(snapshot-entries-can-be-a-baseline)

(let [cmds []]
  (subject.update-addresses
   "ppp0" a1 (merge (dup a1) a2)
   (fn [a] (table.insert cmds a)))
  (expect=
   (doto cmds table.sort)
   [
    ;; order of changes is unimportant
    "ip address change 2001:0:1:2:3/64 dev ppp0 valid_lft 7200 preferred_lft 3600"
    "ip address change 2001:ab:cd:ef/64 dev ppp0 valid_lft 7200 preferred_lft 3600"
    ]))

(let [cmds []]
  (subject.update-addresses
   "ppp0" (merge (dup a1) a2) a1
   (fn [a] (table.insert cmds a)))
  (expect=
   cmds
   [
    ;; deletes are executed before changes
    "ip address del 2001:0:1:2:3/64 dev ppp0 || test $? -eq 2"
    "ip address change 2001:ab:cd:ef/64 dev ppp0 valid_lft 7200 preferred_lft 3600"
    ]))

(print "OK")
