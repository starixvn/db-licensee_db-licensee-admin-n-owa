/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO
 
ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummaryIns]
	@XmlData		XML,
	@Environment	VARCHAR(10)
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Insert licensee reconciliation summary data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#122229]
*/
BEGIN
	SET NOCOUNT ON

	INSERT INTO bodb_licenseeReport.dbo.rptLicenseeReconciliation(
		Environment,
		AccDate,
		PartyId,
		OpeningBalance,
		AmountToCompany,
		ProductFees,
		Discount,
		Rebate,
		ClosingBalance,
		CurrencyName,
		Others,
		Prepayment,
		SettlementDetails)
	SELECT @Environment,
		t.Party.value('@ad', 'DATE')	AS AccDate,
		t.Party.value('@pi', 'INT')		AS PartyId,
		t.Party.value('@ob', 'MONEY')	AS OpeningBalance,
		t.Party.value('@ac', 'MONEY')	AS AmountToCompany,
		t.Party.value('@pf', 'MONEY')	AS ProductFees,
		t.Party.value('@dc', 'MONEY')	AS Discount,
		t.Party.value('@rb', 'MONEY')	AS Rebate,
		t.Party.value('@co', 'MONEY')	AS ClosingBalance,
		t.Party.value('@cn', 'VARCHAR(10)') AS CurrencyName,
		t.Party.value('@ot', 'MONEY')	AS Others,
		t.Party.value('@pp', 'MONEY')	AS Prepayment,
		t.Party.value('text()[1]', 'VARCHAR(4000)')	AS SettlementDetails
	FROM @XmlData.nodes('/root/r') t(Party)

END
GO