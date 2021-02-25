/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200208@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Saba-Club-Integrate-Slot-Game [#FeatureID 147977]
	Description: Insert Into LA_InvoiceItemType record: SBC_Contribution & SBC_JacpotPrize
*/
USE bodb_Licensee
GO

DECLARE @SBC_Contribution INT = 35, @SBC_JacpotPrize INT = 36 

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SBC_Contribution)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SBC_Contribution, 1, 'Income', 1, '', N'Return Saba.club Contribution')
END

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SBC_JacpotPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SBC_JacpotPrize, -1, 'Expense', -1, '', N'Deduct Saba.club Jackpot Prize')
END