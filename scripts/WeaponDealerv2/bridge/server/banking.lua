Bridge = Bridge or {}
Bridge.Banking = {}

function Bridge.Banking.ChargeBuyer(source, amount, reason)
    local account = Config.Payment.Account

    if Bridge.Framework.RemoveMoney(source, account, amount, reason) then
        return true, account
    end

    if Config.Payment.AllowCashFallback and account ~= 'cash' then
        if Bridge.Framework.RemoveMoney(source, 'cash', amount, reason) then
            return true, 'cash'
        end
    end

    return false
end

function Bridge.Banking.DepositSociety(amount)
    if not Config.Payment.Society.Enabled or GetResourceState(Config.Payment.Society.Resource) ~= 'started' then return false end

    local ok = pcall(function()
        exports[Config.Payment.Society.Resource]:AddSocietyMoney(Config.Payment.Society.Account, amount)
    end)

    return ok
end

function Bridge.Banking.RemoveSociety(amount)
    if not Config.Payment.Society.Enabled or GetResourceState(Config.Payment.Society.Resource) ~= 'started' then return true end

    local ok, balance = pcall(function()
        return exports[Config.Payment.Society.Resource]:GetSocietyBalance(Config.Payment.Society.Account)
    end)

    if ok and tonumber(balance or 0) < amount then
        return false
    end

    local removed = pcall(function()
        exports[Config.Payment.Society.Resource]:RemoveSocietyMoney(Config.Payment.Society.Account, amount)
    end)

    return removed == true
end

function Bridge.Banking.GetSocietyBalance()
    if not Config.Payment.Society.Enabled or GetResourceState(Config.Payment.Society.Resource) ~= 'started' then return 0 end

    local ok, balance = pcall(function()
        return exports[Config.Payment.Society.Resource]:GetSocietyBalance(Config.Payment.Society.Account)
    end)

    return ok and tonumber(balance or 0) or 0
end

function Bridge.Banking.AddTransaction(source, transactionType, amount, spendType, name, description)
    if not Config.Payment.PrismTransactionHistory or GetResourceState(Config.Payment.Society.Resource) ~= 'started' then return end

    if type(transactionType) == 'number' then
        description = name
        name = spendType
        spendType = amount
        amount = transactionType
        transactionType = 'withdrawal'
    end

    pcall(function()
        exports[Config.Payment.Society.Resource]:AddBankingTransaction(source, transactionType, amount, spendType, false, name, description)
    end)
end

function Bridge.Banking.PayCommission(employee, saleAmount)
    local cfg = Config.Payment.EmployeeCommission
    if not cfg.Enabled then return 0 end

    local amount = cfg.Type == 'percent' and math.floor(saleAmount * (cfg.Amount / 100)) or cfg.Amount
    if amount <= 0 then return 0 end

    if Bridge.Framework.AddMoney(employee, Config.Payment.Account, amount, 'weapondealer-commission') then
        Bridge.Banking.AddTransaction(
            employee,
            'deposit',
            amount,
            Config.Payment.Account,
            'Weapon Sale Commission',
            ('Commission from legal firearm sale: $%s'):format(amount)
        )
        return amount
    end

    return 0
end
