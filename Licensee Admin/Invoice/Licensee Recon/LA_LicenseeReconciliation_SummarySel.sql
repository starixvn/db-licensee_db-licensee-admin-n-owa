/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummarySel]
	@Month		  DATE
	,@Environment VARCHAR(10)
	,@PartyIds	  VARCHAR(MAX) = ''
	,@PlatformId  TINYINT = 0
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Get licensee reconciliation summary data
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#122229]
		- 20191210@Bruce: Include Promotion amount [#123958]
		- 20210323@Percy: Support duo base currency [RedmineID: #152089]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20220418@Percy: Add Credit for Setup Fees [RedmineID: #164139
		- 20221226@Danny: Integrate Player tips [#180703]
		- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
		- 20241016@Danny: Extend parameter data length [RemineID: #212252]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @reportMonth DATE = DATEADD(MONTH,DATEDIFF(MONTH,0,@Month),0)

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	SELECT 
		AccDate,
		PartyId,
		OpeningBalance,
		AmountToCompany,
		ProductFees,
		Discount,
		Rebate,
		Others,
		ISNULL(Others2,0) Others2,
		Prepayment,
		ISNULL(Promotion,0) Promotion,
		ISNULL(Sponsorship,0) Sponsorship,
		ClosingBalance,
		CurrencyName,
		ISNULL(UPPER(LicenseeCode), '') + '|' + CONVERT(VARCHAR(50), PartyId) AS LicenseeCode,
		ISNULL(PlayerTips,0) PlayerTips
	FROM bodb_licenseeReport.dbo.rptLicenseeReconciliation WITH(NOLOCK)
	WHERE AccDate = @reportMonth AND Environment = @Environment AND (
		ISNULL(@PartyIds,'') = '' OR PartyId IN (SELECT val FROM bodb02.dbo.strSplit(@PartyIds,','))
	)
END
GO