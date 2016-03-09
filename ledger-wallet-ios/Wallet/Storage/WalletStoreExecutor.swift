//
//  WalletStoreExecutor.swift
//  ledger-wallet-ios
//
//  Created by Nicolas Bigot on 07/12/2015.
//  Copyright © 2015 Ledger. All rights reserved.
//

import Foundation

final class WalletStoreExecutor {
    
    private static let logger = Logger.sharedInstance(name: "WalletStoreExecutor")

    // MARK: Accounts management

    class func fetchAllAccounts(context: SQLiteStoreContext) -> [WalletAccount]? {
        let orderStatement = "\(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.indexKey)) ASC"
        return fetchAccounts(orderStatement: orderStatement, context: context)
    }
    
    class func fetchAccountAtIndex(index: Int, context: SQLiteStoreContext) -> WalletAccount? {
        guard let accounts = fetchAccountsAtIndexes([index], context: context) where accounts.count > 0 else { return nil }
        return accounts[0]
    }
    
    class func fetchAccountsAtIndexes(indexes: [Int], context: SQLiteStoreContext) -> [WalletAccount]? {
        guard indexes.count > 0 else { return [] }
        
        let inStatement = indexes.map({ return "\($0)" }).joinWithSeparator(", ")
        let whereStatement = "\(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.indexKey)) IN (\(inStatement))"
        return fetchAccounts(whereStatement: whereStatement, context: context)
    }
    
    class func fetchVisibleAccountsFrom(from: Int, size: Int, order: WalletFetchRequestOrder, context: SQLiteStoreContext) -> [WalletAccount]? {
        let whereStatement = visibleAccountsWhereStatement()
        let orderStatement = "\(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.indexKey)) " + order.representativeStatement
        let limitStatement = "\(from), \(size)"
        return fetchAccounts(whereStatement: whereStatement, orderStatement: orderStatement, limitStatement: limitStatement, context: context)
    }
    
    class func countVisibleAccounts(context: SQLiteStoreContext) -> Int? {
        let whereStatement = visibleAccountsWhereStatement()
        return countAccounts(whereStatement: whereStatement, context: context)
    }
    
    class func visibleAccountsWhereStatement() -> String {
        return
            "(\(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.nextInternalIndexKey)) > 0 OR " +
            "\(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.nextExternalIndexKey)) > 0) AND " +
            "\(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.hiddenKey)) = 0"
    }
    
    private class func fetchAccounts(whereStatement whereStatement: String? = nil, orderStatement: String? = nil, limitStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [WalletAccount]? {
        let fieldsStatement = WalletAccountEntity.allRenamedFieldKeypathsStatement
        var statement = "SELECT \(fieldsStatement) FROM \(WalletAccountEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        if let orderStatement = orderStatement { statement += " ORDER BY \(orderStatement)" }
        if let limitStatement = limitStatement { statement += " LIMIT \(limitStatement)" }
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    private class func countAccounts(whereStatement whereStatement: String? = nil, context: SQLiteStoreContext) -> Int? {
        var statement = "SELECT COUNT(*) FROM \(WalletAccountEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        return countModelCollection(statement, context: context)
    }

    class func addAccount(account: WalletAccount, context: SQLiteStoreContext) -> Bool {
        let fieldsStatement = WalletAccountEntity.allFieldKeysStatement
        let valuesStatement = WalletAccountEntity.allFieldValuesStatement
        let statement = "INSERT INTO \(WalletAccountEntity.tableNameStatement) (\(fieldsStatement)) VALUES (\(valuesStatement))"
        let values = [
            account.index,
            account.name ?? NSNull(),
            account.extendedPublicKey,
            account.nextExternalIndex,
            account.nextInternalIndex,
            NSNumber(longLong: account.balance),
            account.hidden
        ]
        guard context.executeUpdate(statement, withArgumentsInArray: values) else {
            logger.error("Unable to insert account: \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    class func fetchExtendedPublicKeyForAccountAtIndex(index: Int, context: SQLiteStoreContext) -> String? {
        guard let account = fetchAccountAtIndex(index, context: context) else { return nil }
        return account.extendedPublicKey
    }

    // MARK: Layout management
    
    class func setNextIndex(index: Int, forAccountAtIndex accountIndex: Int, external: Bool, context: SQLiteStoreContext) -> Bool {
        guard let currentIndex = fetchNextIndexForAccountAtIndex(accountIndex, external: external, context: context) else { return false }
        guard index > currentIndex else { return true }
        
        let fieldName = WalletAccountEntity.fieldKeyStatement(external ? WalletAccountEntity.nextExternalIndexKey : WalletAccountEntity.nextInternalIndexKey)
        let setStatement = "SET \(fieldName) = ?"
        let whereStatement = "WHERE \(WalletAccountEntity.fieldKeyStatement(WalletAccountEntity.indexKey)) = ?"
        let statement = "UPDATE \(WalletAccountEntity.tableNameStatement) \(setStatement) \(whereStatement)"
        guard context.executeUpdate(statement, withArgumentsInArray: [index, accountIndex]) else {
            logger.error("Unable to set \(fieldName) for account at index \(accountIndex): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    private class func fetchNextIndexForAccountAtIndex(index: Int, external: Bool, context: SQLiteStoreContext) -> Int? {
        let fieldName = WalletAccountEntity.fieldKeypathWithKeyStatement(external ? WalletAccountEntity.nextExternalIndexKey : WalletAccountEntity.nextInternalIndexKey)
        guard let account = fetchAccountAtIndex(index, context: context) else {
            logger.error("Unable to fetch account at index \(index) to fetch \(fieldName): \(context.lastErrorMessage())")
            return nil
        }
        if external {
            return account.nextExternalIndex
        }
        return account.nextInternalIndex
    }
    
    // MARK: Balances management

    class func updateBalanceOfAccounts(accounts: [WalletAccount], context: SQLiteStoreContext) -> Bool {
        guard accounts.count > 0 else { return true }
        
        return accounts.reduce(true) { current, account in
            guard let receivedAmount = fetchTotalReceivedAmountOfAccountAtIndex(account.index, context: context) else { return false }
            guard let sentAmount = fetchTotalSentAmountOfAccountAtIndex(account.index, context: context) else { return false }
            return current && setBalance(receivedAmount - sentAmount, ofAccountAtIndex: account.index, context: context)
        }
    }
    
    private class func setBalance(balance: Int64, ofAccountAtIndex index: Int, context: SQLiteStoreContext) -> Bool {
        let setStatement = "SET \(WalletAccountEntity.fieldKeyStatement(WalletAccountEntity.balanceKey)) = ?"
        let whereStatement = "WHERE \(WalletAccountEntity.fieldKeyStatement(WalletAccountEntity.indexKey)) = ?"
        let statement = "UPDATE \(WalletAccountEntity.tableNameStatement) \(setStatement) \(whereStatement)"
        guard context.executeUpdate(statement, withArgumentsInArray: [NSNumber(longLong: balance), index]) else {
            logger.error("Unable to set balance for account at index \(index): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    private class func fetchTotalReceivedAmountOfAccountAtIndex(index: Int, context: SQLiteStoreContext) -> Int64? {
        let statement = "SELECT IFNULL((SELECT SUM(\"to\".\"\(WalletTransactionOutputEntity.valueKey)\") FROM \"\(WalletTransactionOutputEntity.tableName)\" AS \"to\" INNER JOIN \"\(WalletAddressEntity.tableName)\" AS a ON \"to\".\"\(WalletTransactionOutputEntity.addressKey)\" = a.\"\(WalletAddressEntity.addressKey)\" WHERE a.\"\(WalletAddressEntity.accountIndexKey)\" = ? AND \"to\".\"\(WalletTransactionOutputEntity.transactionHashKey)\" NOT IN (SELECT DISTINCT \"\(WalletDoubleSpendConflictEntity.leftTransactionHashKey)\" FROM \"\(WalletDoubleSpendConflictEntity.tableName)\")), 0) AS \"\(WalletAccountEntity.balanceKey)\""
        guard let results = context.executeQuery(statement, withArgumentsInArray: [index]) where results.next() && !results.columnIsNull(WalletAccountEntity.balanceKey) else {
            logger.error("Unable to compute total received amount of account at index \(index): \(context.lastErrorMessage())")
            return nil
        }
        return results.longLongIntForColumn(WalletAccountEntity.balanceKey)
    }

    private class func fetchTotalSentAmountOfAccountAtIndex(index: Int, context: SQLiteStoreContext) -> Int64? {
        let statement = "SELECT IFNULL((SELECT SUM(\"ti\".\"\(WalletTransactionInputEntity.valueKey)\") FROM \"\(WalletTransactionInputEntity.tableName)\" AS \"ti\" INNER JOIN \"\(WalletAddressEntity.tableName)\" AS a ON \"ti\".\"\(WalletTransactionInputEntity.addressKey)\" = a.\"\(WalletAddressEntity.addressKey)\" WHERE a.\"\(WalletAddressEntity.accountIndexKey)\" = ? AND \"ti\".\"\(WalletTransactionInputEntity.transactionHashKey)\" NOT IN (SELECT DISTINCT \"\(WalletDoubleSpendConflictEntity.leftTransactionHashKey)\" FROM \"\(WalletDoubleSpendConflictEntity.tableName)\")), 0) AS \"\(WalletAccountEntity.balanceKey)\""
        guard let results = context.executeQuery(statement, withArgumentsInArray: [index]) where results.next() && !results.columnIsNull(WalletAccountEntity.balanceKey) else {
            logger.error("Unable to compute total sent amount of account at index \(index): \(context.lastErrorMessage())")
            return nil
        }
        return results.longLongIntForColumn(WalletAccountEntity.balanceKey)
    }

    // MARK: Addresses management
    
    class func fetchAddressesAtPaths(paths: [WalletAddressPath], context: SQLiteStoreContext) -> [WalletAddress]? {
        guard paths.count > 0 else { return [] }
        
        let inStatement = paths.map({ return "\"\($0.representativeString())\"" }).joinWithSeparator(", ")
        let whereStatement = "\(WalletAddressEntity.fieldKeypathWithKeyStatement(WalletAddressEntity.relativePathKey)) IN (\(inStatement))"
        return fetchAddresses(whereStatement: whereStatement, context: context)
    }
    
    class func fetchAddressesWithAddresses(addresses: [String], context: SQLiteStoreContext) -> [WalletAddress]? {
        guard addresses.count > 0 else { return [] }

        let inStatement = addresses.map({ return "\"\($0)\"" }).joinWithSeparator(", ")
        let whereStatement = "\(WalletAddressEntity.fieldKeypathWithKeyStatement(WalletAddressEntity.addressKey)) IN (\(inStatement))"
        return fetchAddresses(whereStatement: whereStatement, context: context)
    }
    
    private class func fetchAddresses(whereStatement whereStatement: String? = nil, orderStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [WalletAddress]? {
        let fieldsStatement = WalletAddressEntity.allRenamedFieldKeypathsStatement
        var statement = "SELECT \(fieldsStatement) FROM \(WalletAddressEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        if let orderStatement = orderStatement { statement += " ORDER BY \(orderStatement)" }
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    class func addAddresses(addresses: [WalletAddress], context: SQLiteStoreContext) -> Bool {
        guard addresses.count > 0 else { return true }
        return addresses.reduce(true) { $0 && addAddress($1, context: context) }
    }
    
    private class func addAddress(address: WalletAddress, context: SQLiteStoreContext) -> Bool {
        guard fetchAddressWithAddress(address.address, context: context) == nil else { return true }
        guard fetchAddressAtPath(address.path, context: context) == nil else { return true }
        
        guard address.path.conformsToBIP32 else {
            logger.error("Unable to add addresses that have not a BIP32 conform address path")
            return false
        }
        
        let fieldsStatement = WalletAddressEntity.allFieldKeysStatement
        let valuesStatement = WalletAddressEntity.allFieldValuesStatement
        let statement = "INSERT INTO \(WalletAddressEntity.tableNameStatement) (\(fieldsStatement)) VALUES (\(valuesStatement))"
        let values: [AnyObject] = [
            address.address,
            address.path.BIP32AccountIndex!,
            address.path.BIP32ChainIndex!,
            address.path.BIP32KeyIndex!,
            address.relativePath
        ]
        guard context.executeUpdate(statement, withArgumentsInArray: values) else {
            logger.error("Unable to insert address: \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    private class func fetchAddressAtPath(path: WalletAddressPath, context: SQLiteStoreContext) -> WalletAddress? {
        guard let results = fetchAddressesAtPaths([path], context: context) where results.count >= 1 else { return nil }
        return results[0]
    }
    
    private class func fetchAddressWithAddress(address: String, context: SQLiteStoreContext) -> WalletAddress? {
        guard let results = fetchAddressesWithAddresses([address], context: context) where results.count >= 1 else { return nil }
        return results[0]
    }
    
    class func fetchCurrentAddressForAccountAtIndex(index: Int, external: Bool, context: SQLiteStoreContext) -> WalletAddress? {
        guard let account = fetchAccountAtIndex(index, context: context) else { return nil }
        let path = WalletAddressPath(BIP32AccountIndex: account.index, chainIndex: external ? 0 : 1, keyIndex: external ? account.nextExternalIndex : account.nextInternalIndex)
        guard let address = fetchAddressAtPath(path, context: context) else { return nil }
        return address
    }
    
    // MARK: Blocks management
    
    class func storeBlocks(blocks: [WalletBlockContainer], context: SQLiteStoreContext) -> Bool {
        guard blocks.count > 0 else { return true }
        return blocks.reduce(true) { $0 && storeBlock($1, context: context) }
    }
    
    private class func storeBlock(block: WalletBlockContainer, context: SQLiteStoreContext) -> Bool {
        guard addBlock(block.block, context: context) else { return false }
        guard block.transactionHashes.count > 0 else { return true }

        let setStatement = "SET \(WalletTransactionEntity.fieldKeyStatement(WalletTransactionEntity.blockHashKey)) = ?"
        let whereStatement = "WHERE \(WalletTransactionEntity.fieldKeyStatement(WalletTransactionEntity.hashKey))"
        let inStatement = "IN (\(block.transactionHashes.map({ "\"\($0)\"" }).joinWithSeparator(", ")))"
        let statement = "UPDATE \(WalletTransactionEntity.tableNameStatement) \(setStatement) \(whereStatement) \(inStatement)"
        
        guard context.executeUpdate(statement, withArgumentsInArray: [block.block.hash]) else {
            logger.error("Unable to store block \(block.block.hash): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    private class func addBlocks(blocks: [WalletBlock], context: SQLiteStoreContext) -> Bool {
        guard blocks.count > 0 else { return true }
        return blocks.reduce(true) { $0 && addBlock($1, context: context) }
    }
    
    private class func addBlock(block: WalletBlock, context: SQLiteStoreContext) -> Bool {
        guard fetchBlockWithHash(block.hash, context: context) == nil else { return true }
        
        let fieldsStatement = WalletBlockEntity.allFieldKeysStatement
        let valuesStatement = WalletBlockEntity.allFieldValuesStatement
        let insertValues: [AnyObject] = [
            block.hash,
            block.height,
            block.time
        ]
        let insertStatement = "INSERT INTO \(WalletBlockEntity.tableNameStatement) (\(fieldsStatement)) VALUES (\(valuesStatement))"
        guard context.executeUpdate(insertStatement, withArgumentsInArray: insertValues) else {
            logger.error("Unable to insert block \(block.hash): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    private class func fetchBlockWithHash(hash: String, context: SQLiteStoreContext) -> WalletBlock? {
        guard let results = fetchBlocksWithHashes([hash], context: context) where results.count > 0 else {
            return nil
        }
        return results[0]
    }
    
    private class func fetchBlocksWithHashes(hashes: [String], context: SQLiteStoreContext) -> [WalletBlock]? {
        let inStatement = hashes.map({ return "\"" + $0 + "\"" }).joinWithSeparator(", ")
        let whereStatement = "\(WalletBlockEntity.fieldKeypathWithKeyStatement(WalletBlockEntity.hashKey)) IN (\(inStatement))"
        return fetchBlocks(whereStatement, values: hashes, context: context)
    }
    
    private class func fetchBlocks(whereStatement: String? = nil, orderStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [WalletBlock]? {
        let fieldsStatement = WalletBlockEntity.allRenamedFieldKeypathsStatement
        var statement = "SELECT \(fieldsStatement) FROM \(WalletBlockEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        if let orderStatement = orderStatement { statement += " ORDER BY \(orderStatement)" }
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    // MARK: Transactions management
    
    class func storeTransactions(transactions: [WalletTransactionContainer], context: SQLiteStoreContext) -> Bool {
        guard transactions.count > 0 else { return true }
        return transactions.reduce(true) { $0 && storeTransaction($1, context: context) }
    }
    
    private class func storeTransaction(transaction: WalletTransactionContainer, context: SQLiteStoreContext) -> Bool {
        if let block = transaction.block {
            guard addBlock(block, context: context) else { return false }
        }
        
        let updateSetStatement = "SET \(WalletTransactionEntity.fieldKeyStatement(WalletTransactionEntity.blockHashKey)) = ?"
        let updateWhereStatement = "WHERE \(WalletTransactionEntity.fieldKeyStatement(WalletTransactionEntity.hashKey)) = ?"
        let updateStatement = "UPDATE \(WalletTransactionEntity.tableNameStatement) \(updateSetStatement) \(updateWhereStatement)"
        let updateValues = [
            transaction.block?.hash ?? NSNull(),
            transaction.transaction.hash
        ]
        guard context.executeUpdate(updateStatement, withArgumentsInArray: updateValues) else {
            logger.error("Unable to update transaction \(transaction.transaction.hash): \(context.lastErrorMessage())")
            return false
        }
        if context.changes() == 0 {
            let insertFieldsStatement = WalletTransactionEntity.allFieldKeysStatement
            let insertValuesStatement = WalletTransactionEntity.allFieldValuesStatement
            let insertStatement = "INSERT INTO \(WalletTransactionEntity.tableNameStatement) (\(insertFieldsStatement)) VALUES (\(insertValuesStatement))"
            let insertValues = [
                transaction.transaction.hash,
                transaction.transaction.receiveAt,
                transaction.transaction.lockTime,
                NSNumber(longLong: transaction.transaction.fees),
                transaction.block?.hash ?? NSNull()
            ]
            guard context.executeUpdate(insertStatement, withArgumentsInArray: insertValues) else {
                logger.error("Unable to insert transaction \(transaction.transaction.hash): \(context.lastErrorMessage())")
                return false
            }
            guard addTransactionInputs(transaction.inputs, context: context) else { return false }
            guard addTransactionOutputs(transaction.outputs, context: context) else { return false }
        }
        return true
    }

    class func fetchTransactionsDoubleSpendingWithTransaction(transaction: WalletTransactionContainer, context: SQLiteStoreContext) -> [WalletTransaction]? {
        guard transaction.regularInputs.count > 0 else { return [] }
        
        let inStatement = transaction.regularInputs.filter({ $0.uid != nil }).map({ "\"\($0.uid!)\"" }).joinWithSeparator(", ")
        let innerJoinStatement = "INNER JOIN \(WalletTransactionEntity.tableNameStatement)"
        let onStatement = "ON \(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionInputEntity.transactionHashKey)) = \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey))"
        let whereStatement =
            "WHERE \(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionInputEntity.uidKey)) IN (\(inStatement)) " +
            "AND \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey)) IS NOT ?"
        let fieldsStatement = WalletTransactionEntity.allRenamedFieldKeypathsStatement
        let statement = "SELECT DISTINCT \(fieldsStatement) FROM \(WalletTransactionInputEntity.tableNameStatement) \(innerJoinStatement) \(onStatement) \(whereStatement)"
        return fetchModelCollection(statement, values: [transaction.transaction.hash], context: context)
    }

    class func fetchTransactionsToResolveFromConflictsOfTransaction(transaction: WalletTransaction, context: SQLiteStoreContext) -> [WalletTransaction]? {
        let innerJoinStatement = "INNER JOIN \(WalletTransactionEntity.tableNameStatement)"
        let onStatement = "ON \(WalletDoubleSpendConflictEntity.fieldKeypathWithKeyStatement(WalletDoubleSpendConflictEntity.rightTransactionHashKey)) = \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey))"
        let whereStatement = "WHERE \(WalletDoubleSpendConflictEntity.fieldKeypathWithKeyStatement(WalletDoubleSpendConflictEntity.leftTransactionHashKey)) = ?"
        let fieldsStatement = WalletTransactionEntity.allRenamedFieldKeypathsStatement
        let statement = "SELECT \(fieldsStatement) FROM \(WalletDoubleSpendConflictEntity.tableNameStatement) \(innerJoinStatement) \(onStatement) \(whereStatement)"
        return fetchModelCollection(statement, values: [transaction.hash], context: context)
    }
    
    private class func fetchTransactionsWithHashes(hashes: [String], context: SQLiteStoreContext) -> [WalletTransaction]? {
        let fieldsStatement = WalletTransactionEntity.allRenamedFieldKeypathsStatement
        let whereStatement = "WHERE \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey))"
        let inStatement = "IN (\(hashes.map({ "\"\($0)\"" }).joinWithSeparator(", ")))"
        let statement = "SELECT \(fieldsStatement) FROM \(WalletTransactionEntity.tableNameStatement) \(whereStatement) \(inStatement)"
        return fetchModelCollection(statement, context: context)
    }
    
    class func countTransactionsWithHashes(hashes: [String], context: SQLiteStoreContext) -> Int? {
        let whereStatement = "WHERE \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey))"
        let inStatement = "IN (\(hashes.map({ "\"\($0)\"" }).joinWithSeparator(", ")))"
        let statement = "SELECT COUNT(*) FROM \(WalletTransactionEntity.tableNameStatement) \(whereStatement) \(inStatement)"
        return countModelCollection(statement, context: context)
    }
    
    class func removeTransactions(transactions: [WalletTransaction], context: SQLiteStoreContext) -> Bool {
        let inStatement = transactions.map({ return "\"\($0.hash)\"" }).joinWithSeparator(", ")
        let whereStatement = "WHERE \(WalletTransactionEntity.fieldKeyStatement(WalletTransactionEntity.hashKey)) IN (\(inStatement))"
        let statement = "DELETE FROM \(WalletTransactionEntity.tableNameStatement) \(whereStatement)"
        guard context.executeUpdate(statement, withArgumentsInArray: nil) else {
            logger.error("Unable to remove transactions: \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    // MARK: Transaction inputs management
    
    private class func addTransactionInputs(inputs: [WalletTransactionInput], context: SQLiteStoreContext) -> Bool {
        guard inputs.count > 0 else { return true }
        
        for input in inputs {
            let insertFieldsStatement = WalletTransactionInputEntity.allFieldKeysStatement
            let insertValuesStatement = WalletTransactionInputEntity.allFieldValuesStatement
            let insertValues = [
                input.uid ?? NSNull(),
                input.outputHash ?? NSNull(),
                input.outputIndex != nil ? NSNumber(unsignedInt: input.outputIndex!) : NSNull(),
                NSNumber(longLong: input.value ?? 0),
                input.scriptSignature ?? NSNull(),
                input.address ?? NSNull(),
                input.coinbase,
                NSNumber(unsignedInt: input.index),
                input.transactionHash
            ]
            
            let insertStatement = "INSERT INTO \(WalletTransactionInputEntity.tableNameStatement) (\(insertFieldsStatement)) VALUES (\(insertValuesStatement))"
            guard context.executeUpdate(insertStatement, withArgumentsInArray: insertValues) else {
                logger.error("Unable to insert input for transaction \(insertValues.last!): \(context.lastErrorMessage())")
                return false
            }
        }
        return true
    }
    
    class func fetchTransactionInputsForTransactionHash(hash: String, context: SQLiteStoreContext) -> [WalletTransactionInput]? {
        let whereStatement = "\(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.transactionHashKey)) = ?"
        let orderStatement = "\(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.indexKey)) ASC"
        let values = [hash]
        return fetchTransactionInputs(whereStatement, orderStatement: orderStatement, values: values, context: context)
    }
    
    private class func fetchTransactionInputs(whereStatement: String? = nil, orderStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [WalletTransactionInput]? {
        let fieldsStatement = WalletTransactionInputEntity.allRenamedFieldKeypathsStatement
        var statement = "SELECT \(fieldsStatement) FROM \(WalletTransactionInputEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        if let orderStatement = orderStatement { statement += " ORDER BY \(orderStatement)" }
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    // MARK: Transaction outputs management
    
    private class func addTransactionOutputs(outputs: [WalletTransactionOutput], context: SQLiteStoreContext) -> Bool {
        guard outputs.count > 0 else { return true }
        
        for output in outputs {
            let insertFieldsStatement = WalletTransactionOutputEntity.allFieldKeysStatement
            let insertValuesStatement = WalletTransactionOutputEntity.allFieldValuesStatement
            let insertValues = [
                output.scriptHex,
                NSNumber(longLong: output.value),
                output.address ?? NSNull(),
                NSNumber(unsignedInt: output.index),
                output.transactionHash
            ]
            let insertStatement = "INSERT INTO \(WalletTransactionOutputEntity.tableNameStatement) (\(insertFieldsStatement)) VALUES (\(insertValuesStatement))"
            guard context.executeUpdate(insertStatement, withArgumentsInArray: insertValues) else {
                logger.error("Unable to insert output for transaction \(output.transactionHash): \(context.lastErrorMessage())")
                return false
            }
        }
        return true
    }

    class func fetchTransactionOutputsForTransactionHash(hash: String, context: SQLiteStoreContext) -> [WalletTransactionOutput]? {
        let whereStatement = "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.transactionHashKey)) = ?"
        let orderStatement = "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.indexKey)) ASC"
        let values = [hash]
        return fetchTransactionOutputs(whereStatement, orderStatement: orderStatement, values: values, context: context)
    }

    class func fetchUnspentTransactionOutputsFromAccountAtIndex(index: Int, context: SQLiteStoreContext) -> [WalletUnspentTransactionOutput]? {
        let fieldsStatement =
            WalletTransactionOutputEntity.allRenamedFieldKeypathsStatement + ", " +
            WalletAddressEntity.allRenamedFieldKeypathsStatement
        let leftJoinTransactionInputsStatement =
            "LEFT JOIN \(WalletTransactionInputEntity.tableNameStatement) ON" +
            "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.indexKey)) = \(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionInputEntity.outputIndexKey)) AND " +
            "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.transactionHashKey)) = \(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionInputEntity.outputHashKey))"
        let innerJoinAddressesStatement =
            "INNER JOIN \(WalletAddressEntity.tableNameStatement) ON" +
            "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.addressKey)) = \(WalletAddressEntity.fieldKeypathWithKeyStatement(WalletAddressEntity.addressKey))"
        let innerJoinTransactionsStatement =
            "INNER JOIN \(WalletTransactionEntity.tableNameStatement) ON" +
            "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.transactionHashKey)) = \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey))"
        let leftJoinBlocksStatement =
            "LEFT JOIN \(WalletBlockEntity.tableNameStatement) ON" +
            "\(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.blockHashKey)) = \(WalletBlockEntity.fieldKeypathWithKeyStatement(WalletBlockEntity.hashKey))"
        let leftJoinConfictsStatement =
            "LEFT JOIN \(WalletDoubleSpendConflictEntity.tableNameStatement) ON" +
            "\(WalletTransactionOutputEntity.fieldKeypathWithKeyStatement(WalletTransactionOutputEntity.transactionHashKey)) = \(WalletDoubleSpendConflictEntity.fieldKeypathWithKeyStatement(WalletDoubleSpendConflictEntity.leftTransactionHashKey))"
        let whereStatement =
            "WHERE \(WalletAddressEntity.fieldKeypathWithKeyStatement(WalletAddressEntity.accountIndexKey)) = ? AND " +
            "\(WalletTransactionInputEntity.fieldKeypathWithKeyStatement(WalletTransactionInputEntity.uidKey)) IS NULL AND " +
            "\(WalletDoubleSpendConflictEntity.fieldKeypathWithKeyStatement(WalletDoubleSpendConflictEntity.leftTransactionHashKey)) IS NULL"
        let orderByStatement =
            "ORDER BY (CASE WHEN \(WalletBlockEntity.fieldKeypathWithKeyStatement(WalletBlockEntity.heightKey)) IS NULL THEN 0 ELSE 1 END) DESC, " +
            "\(WalletBlockEntity.fieldKeypathWithKeyStatement(WalletBlockEntity.heightKey)) ASC"
        let statement =
            "SELECT \(fieldsStatement) FROM \(WalletTransactionOutputEntity.tableNameStatement) " +
                "\(leftJoinTransactionInputsStatement) \(innerJoinAddressesStatement) \(innerJoinTransactionsStatement) \(leftJoinBlocksStatement) \(leftJoinConfictsStatement)" +
                "\(whereStatement) \(orderByStatement)"
        return fetchModelCollection(statement, values: [index], context: context)
    }
    
    private class func fetchTransactionOutputs(whereStatement: String? = nil, orderStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [WalletTransactionOutput]? {
        let fieldsStatement = WalletTransactionOutputEntity.allRenamedFieldKeypathsStatement
        var statement = "SELECT \(fieldsStatement) FROM \(WalletTransactionOutputEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        if let orderStatement = orderStatement { statement += " ORDER BY \(orderStatement)" }
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    // MARK: Operations management
    
    class func storeOperations(operations: [WalletOperation], context: SQLiteStoreContext) -> Bool {
        guard operations.count > 0 else { return true }
        
        return operations.reduce(true) { $0 && storeOperation($1, context: context) }
    }
    
    private class func storeOperation(operation: WalletOperation, context: SQLiteStoreContext) -> Bool {
        let updateFieldsStatement = "\(WalletOperationEntity.fieldKeyStatement(WalletOperationEntity.amountKey)) = ?"
        let updateSetStatement = "SET \(updateFieldsStatement)"
        let updateWhereStatement = "WHERE \(WalletOperationEntity.fieldKeyStatement(WalletOperationEntity.uidKey)) = ?"
        let updateStatement = "UPDATE \(WalletOperationEntity.tableNameStatement) \(updateSetStatement) \(updateWhereStatement)"
        let updateValues = [NSNumber(longLong: operation.amount), operation.uid]
        guard context.executeUpdate(updateStatement, withArgumentsInArray: updateValues) else {
            logger.error("Unable to update operation \(operation.uid): \(context.lastErrorMessage())")
            return false
        }
        if context.changes() == 0 {
            let insertFieldsStatement = WalletOperationEntity.allFieldKeysStatement
            let insertValuesStatement = WalletOperationEntity.allFieldValuesStatement
            let insertStatement = "INSERT INTO \(WalletOperationEntity.tableNameStatement) (\(insertFieldsStatement)) VALUES (\(insertValuesStatement))"
            let insertValues = [
                operation.uid,
                NSNumber(longLong: operation.amount),
                operation.kind.rawValue,
                operation.transactionHash,
                operation.accountIndex,
            ]
            guard context.executeUpdate(insertStatement, withArgumentsInArray: insertValues) else {
                logger.error("Unable to insert operation \(operation.uid): \(context.lastErrorMessage())")
                return false
            }
        }
        return true
    }
    
    // MARK: Account operations management
    
    class func fetchVisibleAccountOperationsForAccountAtIndex(index: Int?, from: Int, size: Int, order: WalletFetchRequestOrder, context: SQLiteStoreContext) -> [WalletAccountOperationContainer]? {
        guard let containers = fetchVisibleAccountOperationPartialContainers(index, from: from, size: size, order: order, context: context) else { return nil }
    
        var objects: [WalletAccountOperationContainer] = []
        for container in containers {
            guard let
                inputs = fetchTransactionInputsForTransactionHash(container.transaction.hash, context: context),
                outputs = fetchTransactionOutputsForTransactionHash(container.transaction.hash, context: context)
            else {
                logger.error("Unable for fetch inputs and outputs of transaction \(container.transaction.hash) to create account operations: \(context.lastErrorMessage())")
                return nil
            }
            
            let transactionContainer = WalletTransactionContainer(transaction: container.transaction, inputs: inputs, outputs: outputs, block: container.block)
            let operationContainer = WalletOperationContainer(operation: container.operation, transactionContainer: transactionContainer)
            let accountOperationContainer = WalletAccountOperationContainer(account: container.account, operationContainer: operationContainer)
            objects.append(accountOperationContainer)
        }
        return objects
    }
    
    class func countVisibleAccountOperationsForAccountAtIndex(index: Int?, context: SQLiteStoreContext) -> Int? {
        let whereStatement = visibleAccountOperationsWhereStatementForAccountAtIndex(index)
        return countVisibleAccountOperationPartialContainers(whereStatement, values: index != nil ? [index!] : [], context: context)
    }
    
    private class func fetchVisibleAccountOperationPartialContainers(accountIndex: Int?, from: Int, size: Int, order: WalletFetchRequestOrder, context: SQLiteStoreContext) -> [WalletAccountOperationPartialContainer]? {
        let fieldsStatement =
        WalletAccountEntity.allRenamedFieldKeypathsStatement + ", " +
            WalletOperationEntity.allRenamedFieldKeypathsStatement + ", " +
            WalletTransactionEntity.allRenamedFieldKeypathsStatement + ", " +
            WalletBlockEntity.allRenamedFieldKeypathsStatement
        
        let innerJoinTransactionsStatement =
            "INNER JOIN \(WalletTransactionEntity.tableNameStatement) " +
            "ON \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.hashKey)) = \(WalletOperationEntity.fieldKeypathWithKeyStatement(WalletOperationEntity.transactionHashKey))"
        let innerJoinBlockStatement =
            "LEFT JOIN \(WalletBlockEntity.tableNameStatement)" +
            "ON \(WalletBlockEntity.fieldKeypathWithKeyStatement(WalletBlockEntity.hashKey)) = \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.blockHashKey))"
        let innerJoinAccountStatement =
            "INNER JOIN \(WalletAccountEntity.tableNameStatement)" +
            "ON \(WalletAccountEntity.fieldKeypathWithKeyStatement(WalletAccountEntity.indexKey)) = \(WalletOperationEntity.fieldKeypathWithKeyStatement(WalletOperationEntity.accountIndexKey))"
        let whereStatement = "WHERE " + visibleAccountOperationsWhereStatementForAccountAtIndex(accountIndex)
        let orderByStatement = "ORDER BY \(WalletTransactionEntity.fieldKeypathWithKeyStatement(WalletTransactionEntity.receptionDateKey)) " + order.representativeStatement
        let limitStatement = "LIMIT \(from), \(size)"
        let values = accountIndex != nil ? [accountIndex!] : []
        let statement =
            "SELECT \(fieldsStatement) FROM \(WalletOperationEntity.tableNameStatement) " +
            "\(innerJoinTransactionsStatement) \(innerJoinBlockStatement) \(innerJoinAccountStatement) " +
            "\(whereStatement) \(orderByStatement) \(limitStatement)"
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    private class func countVisibleAccountOperationPartialContainers(whereStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> Int? {
        var statement = "SELECT COUNT(*) FROM \(WalletOperationEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        return countModelCollection(statement, values: values, context: context)
    }
    
    private class func visibleAccountOperationsWhereStatementForAccountAtIndex(accountIndex: Int?) -> String {
        return accountIndex != nil ? "\(WalletOperationEntity.fieldKeypathWithKeyStatement(WalletOperationEntity.accountIndexKey)) = ?" : ""
    }
    
    // MARK: Double spend conflicts management
    
    class func addDoubleSpendConflicts(conflicts: [WalletDoubleSpendConflict], context: SQLiteStoreContext) -> Bool {
        guard conflicts.count > 0 else { return true }
        return conflicts.reduce(true, combine: { $0 && addDoubleSpendConflict($1, context: context) })
    }
    
    private class func addDoubleSpendConflict(conflict: WalletDoubleSpendConflict, context: SQLiteStoreContext) -> Bool {
        guard fetchDoubleSpendConflict(conflict, context: context) == nil else { return true }
        
        let fieldsStatement = WalletDoubleSpendConflictEntity.allFieldKeysStatement
        let valuesStatement = WalletDoubleSpendConflictEntity.allFieldValuesStatement
        let statement = "INSERT INTO \(WalletDoubleSpendConflictEntity.tableNameStatement) (\(fieldsStatement)) VALUES (\(valuesStatement))"
        let values = [conflict.leftTransactionHash, conflict.rightTransactionHash]
        guard context.executeUpdate(statement, withArgumentsInArray: values) else {
            logger.error("Unable to insert double spend conflict \(conflict.leftTransactionHash) <-> \(conflict.rightTransactionHash): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    private class func fetchDoubleSpendConflict(conflict: WalletDoubleSpendConflict, context: SQLiteStoreContext) -> WalletDoubleSpendConflict? {
        let whereStatement =
            "\(WalletDoubleSpendConflictEntity.fieldKeypathWithKeyStatement(WalletDoubleSpendConflictEntity.leftTransactionHashKey)) = ? AND " +
            "\(WalletDoubleSpendConflictEntity.fieldKeypathWithKeyStatement(WalletDoubleSpendConflictEntity.rightTransactionHashKey)) = ?"
        guard let results = fetchDoubleSpendConflicts(whereStatement, values: [conflict.leftTransactionHash, conflict.rightTransactionHash], context: context) where results.count > 0 else {
            return nil
        }
        return results[0]
    }
    
    private class func fetchDoubleSpendConflicts(whereStatement: String? = nil, orderStatement: String? = nil, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [WalletDoubleSpendConflict]? {
        let fieldsStatement = WalletDoubleSpendConflictEntity.allRenamedFieldKeypathsStatement
        var statement = "SELECT \(fieldsStatement) FROM \(WalletDoubleSpendConflictEntity.tableNameStatement)"
        if let whereStatement = whereStatement { statement += " WHERE \(whereStatement)" }
        if let orderStatement = orderStatement { statement += " ORDER BY \(orderStatement)" }
        return fetchModelCollection(statement, values: values, context: context)
    }
    
    // MARK: Schema management
    
    class func schemaVersion(context: SQLiteStoreContext) -> Int? {
        let statement = "SELECT \(WalletMetadataEntity.schemaVersionKey) FROM \(WalletMetadataEntity.tableNameStatement)"
        guard let results = context.executeQuery(statement, withArgumentsInArray: nil) else {
            logger.warn("Unable to fetch schema version: \(context.lastErrorMessage())")
            return nil
        }
        guard results.next() && !results.columnIsNull(WalletMetadataEntity.schemaVersionKey) else {
            logger.error("Unable to fetch schema version: no row")
            return nil
        }
        let version = results.longForColumn(WalletMetadataEntity.schemaVersionKey)
        guard version > 0 else {
            logger.error("Unable to fetch schema version: value is <= 0")
            return nil
        }
        return version
    }

    class func updateMetadata(metadata: [String: AnyObject], context: SQLiteStoreContext) -> Bool {
        guard metadata.count > 0 else { return true }
        
        let updateFieldsStatement = metadata.map { return "\"\($0.0)\" = :\($0.0)" }.joinWithSeparator(", ")
        let updateSetStatement = "SET \(updateFieldsStatement)"
        let updateStatement = "UPDATE \(WalletMetadataEntity.tableNameStatement) \(updateSetStatement)"
        guard context.executeUpdate(updateStatement, withParameterDictionary: metadata) else {
            logger.error("Unable to set database metadata \(metadata): \(context.lastErrorMessage())")
            return false
        }
        if context.changes() == 0 {
            let insertFieldsStatement = metadata.map { "\"\($0.0)\"" }.joinWithSeparator(", ")
            let insertValuesStatement = metadata.map { ":\($0.0)" }.joinWithSeparator(", ")
            let insertStatement = "INSERT INTO \(WalletMetadataEntity.tableNameStatement) (\(insertFieldsStatement)) VALUES (\(insertValuesStatement))"
            guard context.executeUpdate(insertStatement, withParameterDictionary: metadata) else {
                logger.error("Unable to set database metadata \(metadata): \(context.lastErrorMessage())")
                return false
            }
        }
        return true
    }
    
    class func executePragmaCommand(statement: String, context: SQLiteStoreContext) -> Bool {
        guard let _ = context.executeQuery(statement, withArgumentsInArray: nil) else {
            logger.error("Unable to execute pragma command \(statement): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    class func executeTableCreation(statement: String, context: SQLiteStoreContext) -> Bool {
        guard context.executeUpdate(statement, withArgumentsInArray: nil) else {
            logger.error("Unable to execute table creation \(statement): \(context.lastErrorMessage())")
            return false
        }
        return true
    }
    
    // MARK: Internal methods
    
    private class func fetchModel<T: SQLiteFetchableModel>(statement: String, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> T? {
        guard let results = context.executeQuery(statement, withArgumentsInArray: values) else {
            logger.error("Unable to fetch model of type \(T.self): \(context.lastErrorMessage())")
            return nil
        }
        guard results.next() else {
            return nil
        }
        return T.init(resultSet: results)
    }
    
    private class func fetchModelCollection<T: SQLiteFetchableModel>(statement: String, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> [T]? {
        guard let results = context.executeQuery(statement, withArgumentsInArray: values) else {
            logger.error("Unable to fetch model collection of type \(T.self): \(context.lastErrorMessage())")
            return nil
        }
        return T.collectionFromResultSet(results)
    }
    
    private class func countModelCollection(statement: String, values: [AnyObject]? = nil, context: SQLiteStoreContext) -> Int? {
        guard let results = context.executeQuery(statement, withArgumentsInArray: values) else {
            logger.error("Unable to count model collection: \(context.lastErrorMessage())")
            return nil
        }
        guard results.next() else {
            return nil
        }
        guard let count = results.objectForColumnIndex(0) where count is NSNumber else {
            logger.error("Unable to count model collection: column 0 is not a number")
            return nil
        }
        let number = count as! NSNumber
        return number.integerValue
    }

}