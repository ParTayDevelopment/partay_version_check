Bridge = Bridge or {}
Bridge.Phone = {}

local function enabled()
    return Config.Phone
        and Config.Phone.Enabled
        and Config.Phone.OrderEmail
        and Config.Phone.OrderEmail.Enabled
        and GetResourceState(Config.Phone.Resource) == 'started'
end

local function orderList(prepared, orderIds)
    local rows = {}

    for index, entry in ipairs(prepared) do
        local weapon = entry.weapon
        local attachments = {}

        for _, attachment in ipairs((entry.attachments and entry.attachments.items) or {}) do
            attachments[#attachments + 1] = attachment.label or attachment.item
        end

        rows[#rows + 1] = ('Order #%s - %s%s - Ready: %s'):format(
            orderIds[index] or 'Pending',
            weapon.label,
            #attachments > 0 and (' with ' .. table.concat(attachments, ', ')) or '',
            entry.readyAt
        )
    end

    return table.concat(rows, '\n')
end

function Bridge.Phone.SendOrderEmail(source, store, scan, orderIds, prepared, total, paymentMethod)
    if not enabled() then return false end

    local ok, success, reason = pcall(function()
        local phoneNumber = exports[Config.Phone.Resource]:GetEquippedPhoneNumber(source)
        if not phoneNumber then return false, 'no_phone' end

        local email = exports[Config.Phone.Resource]:GetEmailAddress(phoneNumber)
        if not email then return false, 'no_email' end

        local cfg = Config.Phone.OrderEmail
        local message = ([[
Your legal firearm order has been approved.

Customer: %s
Store: %s
Seller: %s
Payment: %s
Total: $%s

%s

Bring valid identification when collecting approved firearms. This email is a confirmation notice only; pickup is verified against the registry.
        ]]):format(
            scan.buyerName,
            store.label,
            Bridge.Framework.GetName(scan.employee),
            paymentMethod,
            total,
            orderList(prepared, orderIds)
        )

        local success, mailId = exports[Config.Phone.Resource]:SendMail({
            to = email,
            sender = cfg.Sender or store.label,
            subject = cfg.Subject or 'Legal Firearm Order Confirmation',
            message = message
        })

        return success == true, mailId or 'send_failed'
    end)

    if ok and success == true then
        return true
    end

    Server.Logs.Write('phone_email_failed', 'LB Phone order confirmation email failed.', {
        buyer = scan.citizenid,
        orders = orderIds,
        reason = ok and tostring(reason or 'send_failed') or 'export_error'
    })

    return false
end

local function sendSimpleMail(source, store, subject, message)
    if not enabled() then return false end

    local ok, success, reason = pcall(function()
        local phoneNumber = exports[Config.Phone.Resource]:GetEquippedPhoneNumber(source)
        if not phoneNumber then return false, 'no_phone' end

        local email = exports[Config.Phone.Resource]:GetEmailAddress(phoneNumber)
        if not email then return false, 'no_email' end

        local cfg = Config.Phone.OrderEmail
        local success, mailId = exports[Config.Phone.Resource]:SendMail({
            to = email,
            sender = cfg.Sender or store.label,
            subject = subject,
            message = message
        })

        return success == true, mailId or 'send_failed'
    end)

    if ok and success == true then return true end

    Server.Logs.Write('phone_email_failed', 'LB Phone status email failed.', {
        subject = subject,
        reason = ok and tostring(reason or 'send_failed') or 'export_error'
    })

    return false
end

function Bridge.Phone.SendClearanceEmail(source, store, order)
    return sendSimpleMail(source, store, 'Firearm Order In Clearance', ([[
Your firearm order has entered clearance processing.

Store: %s
Order: #%s
Firearm: %s

You will receive another notice when the order is ready for pickup.
    ]]):format(store.label, order.id, order.weapon_label))
end

function Bridge.Phone.SendReadyEmail(source, store, order)
    return sendSimpleMail(source, store, 'Firearm Order Ready For Pickup', ([[
Your registered firearm order is ready for pickup.

Store: %s
Order: #%s
Firearm: %s

Bring valid identification to the secure pickup counter.
    ]]):format(store.label, order.id, order.weapon_label))
end
