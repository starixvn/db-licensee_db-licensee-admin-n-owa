/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200714@Parsons
	DB: DBCUST.bodb_Licensee
	Task: LA-Implement-PP-Jackpot [#FeatureID 137306]
	Description: Insert Into LA_InvoiceItemType record: PP_Contribution & PP_JacpotPrize
*/
USE bodb_Licensee
GO

DECLARE @PPContribution INT = 31, @PPJacpotPrize INT = 32 

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PPContribution)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PPContribution, 1, 'Income', 1, '', N'PP Contribution')
END

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PPJacpotPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PPJacpotPrize, -1, 'Expense', -1, '', N'PP Jackpot Prize')
END