/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20241003@Sally
	DB: DBCUST.bodb_Licensee
	Task: Support Odds Boost Voucher [#209884]
	 - Initialize new LA_InvoiceItemType
*/
USE bodb_Licensee
GO

DECLARE @SB_OddsBoostBonus INT = 61

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SB_OddsBoostBonus)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SB_OddsBoostBonus, -1, 'Expense', -1, '', N'Deduct Sportsbook Odds Boost Bonus')
END
