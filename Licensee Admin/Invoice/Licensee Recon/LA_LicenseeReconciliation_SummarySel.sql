/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO
--use bodb_licenseeReport
--grant execute on [LA_LicenseeReconciliation_SummarySel] to bodbAdminNet
--GRANT SELECT ON dbo.rptLicenseeReconciliation TO bodbAdminNet  
ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummarySel]
	@Month	DATE,
	@Environment VARCHAR(10)
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Get licensee reconciliation summary data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#120220]
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