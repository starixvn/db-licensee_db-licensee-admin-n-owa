/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummarySel]
	@Month	DATE,
	@Environment VARCHAR(10),
	@PartyIds VARCHAR(4000) = ''
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Get licensee reconciliation summary data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#122229]
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
		Others,
		Prepayment,
		ClosingBalance,
		CurrencyName
	FROM bodb_licenseeReport.dbo.rptLicenseeReconciliation WITH(NOLOCK)
	WHERE AccDate = @reportMonth AND Environment = @Environment AND (
		ISNULL(@PartyIds,'') = '' OR PartyId IN (SELECT val FROM bodb02.dbo.strSplit(@PartyIds,','))
	)
END
GO