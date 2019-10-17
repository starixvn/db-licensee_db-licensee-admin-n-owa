/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO
 
ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummaryIns]
	@AccDate			DATE,
	@PartyId			INT,
	@OpeningBalance		MONEY,
	@AmountToCompany	MONEY,
	@ProductFees		MONEY,
	@Discount			MONEY,
	@Rebate				MONEY,
	@Others				MONEY,
	@Prepayment			MONEY,
	@ClosingBalance		MONEY,
	@CurrencyName		VARCHAR(10),
	@SettlementDetails	VARCHAR(4000),
	@Environment		VARCHAR(10)
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Insert licensee reconciliation summary data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#112229]
*/
BEGIN
	SET NOCOUNT ON

	INSERT INTO bodb_licenseeReport.dbo.rptLicenseeReconciliation(
		AccDate,
		PartyId,
		OpeningBalance,
		AmountToCompany,
		ProductFees,
		Discount,
		Rebate,
		ClosingBalance,
		CurrencyName,
		SettlementDetails,
		Environment,
		Others,
		Prepayment)
	VALUES(
		@AccDate,
		@PartyId,
		@OpeningBalance,
		@AmountToCompany,
		@ProductFees,
		@Discount,
		@Rebate,
		@ClosingBalance,
		@CurrencyName,
		@SettlementDetails,
		@Environment,
		@Others,
		@Prepayment)

END
GO