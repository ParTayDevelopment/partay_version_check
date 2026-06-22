# qbx_weapondealer

Legal firearm sales and registration workflow for a realistic Qbox server.

## Dependencies

- qbx_core, qb-core, or es_extended depending on `Config.Framework.Name`
- ox_lib
- ox_inventory
- ox_target
- oxmysql
- cs_license
- lb-tablet, optional but enabled by default
- lb-phone, optional but enabled by default for order confirmation email
- prism_banking, optional but enabled by default for society deposits and transaction history

## UI

The sales desk, order stations, pickup counter, and firing range open a custom right-center NUI named `Legal Firearm Registry`.
The NUI background is transparent and the panel is compact, so it works as an in-world terminal instead of a full-screen menu.
ox_lib is still used for notifications and buyer document-scan consent.
The terminal includes active order countdowns and customer profiles built from successful document scans.
Document intake uses a required consent popup and a configurable license-record verification delay.
Buyer-facing order stations use weapon cards with ox_inventory images, ammo type, price, wait time, and a nearby-visible floating weapon preview.
Weapon cards also support weapon packages and optional physical attachment items delivered with the registered weapon at pickup.
Employee assembly stations use a spawned armoury prop and a store parts stash to assemble pending firearm orders before clearance timers begin.
Verified buyers can apply one eligible firearm trade-in as order credit. Registered store-purchased firearms receive the configured bonus window value, while unowned or unregistered firearms use the lower buyback value.

## Install

1. Place this folder in your resources directory as `qbx_weapondealer`.
2. Import `sql/install.sql`.
   - Existing installs should also run `sql/update_1.2_order_safety.sql`, `sql/update_1.3_attachments.sql`, `sql/update_1.4_assembly.sql`, `sql/update_1.5_parts_ordering.sql`, `sql/update_1.6_trade_ins.sql`, and `sql/update_1.7_pickup_items.sql`.
3. Add `ensure qbx_weapondealer` after the dependencies in `server.cfg`.
4. Confirm ox_inventory contains the configured weapon items, `id_card`, and `weaponlicense`.
5. Copy the entries from `ox_inventory_items.lua` into `ox_inventory/data/items.lua`.
6. Confirm ox_inventory contains the configured weapon definitions in `ox_inventory/data/weapons.lua`.
7. Add or adjust the configured attachment items from `config/weapons.lua` to match your attachment system.
8. Edit `config/config.lua` and `config/weapons.lua` for your job, grades, prices, wait times, packages, attachments, assembly recipes, stock ordering, and locations.

The default weapon catalog uses standard ox_inventory weapon item names such as `WEAPON_PISTOL`.
The default attachment item names are examples. Match them to your ox_inventory attachment system before going live.

The included `ox_inventory_items.lua` contains the default document, receipt, ammo, attachment, and assembly component items used by this resource.

## Current Defaults

- Job: `gunstore`
- Framework: `qbox`
- Scan/order/test/pickup grade: `1`
- Duty required: enabled
- ID item: `id_card`
- Weapon license item: `weaponlicense`
- LB Tablet MDT: `police`
- LB Phone order email: enabled
- Prism society account: `gunstore`
- Payment: bank first, cash fallback enabled
- Employee commission: 5 percent
- Receipt item: `weapon_receipt`
- Receipt requirement: optional by default, best-effort issue after order approval
- License record check delay: 3 to 7 seconds
- Weapon preview coords: `16.6942, -1102.1113, 29.8020, 292.4817`

## Flow

1. Employee uses the ox_target sales desk.
2. Employee selects a nearby customer and swipes documents.
3. Server validates employee job/duty/grade, proximity, ID metadata, weapon license metadata, buyer citizenid, and cs_license status.
4. Buyer uses an order station to choose weapons, accessories, melee items, optional trade-in credit, and payment from one shared secure cart. The seller is attached from the document scan.
5. Server validates the selected trade-in slot, removes the traded weapon only during checkout, creates protected `pending_assembly` rows, charges the net amount, issues a receipt item, deposits society money, and pays commission.
6. Employee uses the assembly station prop to assemble pending orders from the store parts stash.
7. Assembly moves the order into clearance processing and starts the configured wait timer.
8. Qualified employees can use the registry Stock Order tab to purchase replacement parts with society, bank, or cash funds.
9. Parts stock orders are delivered directly into the configured store stash after the delivery timer.
10. Once ready, the buyer uses the pickup target.
11. Server verifies ownership, creates a serial for firearm orders, releases pickup items through ox_inventory, stores firearm registration, and sends firearm serials to LB Tablet.

## Notes

- `cs_license` is used through documented exports only because the supplied resource is escrowed.
- LB Tablet stores the final registered weapon through `RegisterMDTWeapon`; this resource keeps the full order and audit history.
- LB Phone sends a Mail app confirmation after order approval when the buyer has an equipped phone with an email account.
- Employee commission is paid to the employee who verified the buyer documents. Order stations do not guess the seller at checkout.
- Employees can verify multiple customers in one store session. The Profile and Active tabs track the selected verified customer, while buyer order stations remain buyer-specific.
- Trade-ins are checkout credit, not instant cash. The server re-checks the selected inventory slot and serial at purchase time, caps the credit to the configured order percent, and logs accepted trade-ins in `weapon_trade_ins`.
- Attachment packages and individual attachments are validated and priced on the server. Attachments are physical ox_inventory items issued at pickup with purchase metadata tied to the firearm serial.
- Accessory, ammo, and melee sales are queued as secure pickup items. They are paid at checkout, then released by the pickup ped instead of going directly into inventory.
- Assembly consumes configured weapon component items from the store stash, not employee inventory. This keeps the business stock workflow ready for a supplier/order system later.
- Parts stock ordering deposits delivered items directly into the store stash. Ordered parts never enter employee inventory.
- Order station previews are validated by the server and rendered for nearby clients within 25 units. They clear on close or after 30 seconds.
- A per-customer server lock blocks double-submit race attempts. If a paid order insert fails, the script deletes partial rows, attempts an automatic refund, and writes an audit log.
- Test weapons are issued as temporary ox_inventory weapon items and equipped through ox_inventory, then removed on timeout, death, disconnect, or leaving the range.
- All sensitive actions are checked on the server. Client callbacks only request actions.
- Saved customer profiles are for registry history and convenience. New weapon orders still require a fresh document scan.
