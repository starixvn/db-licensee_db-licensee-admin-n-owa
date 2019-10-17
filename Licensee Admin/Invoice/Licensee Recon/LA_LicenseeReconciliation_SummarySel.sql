/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummarySel]
	@Month	DATE,
	@Environment VARCHAR(10)
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Get licensee reconciliation summary data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#112229]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @reportMonth DATE = DATEADD(MONTH,DATEDIFF(MONTH,0,@Month),0)

	SELECT 
		AccDate,
		PartyId,
		OpeningBalance,
		AmountToCompany,
		ProductFees,
		Discount,
		Rebate,
		ClosingBalance,
		CurrencyName,
		SettlementDetails
	FROM bodb_licenseeReport.dbo.rptLicenseeReconciliation WITH(NOLOCK)
	WHERE AccDate = @reportMonth AND Environment = @Environment
END
GO