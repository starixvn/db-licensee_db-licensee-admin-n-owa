/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerInfoSel]
	 @PayerId	INT	= 0,
	 @BillerId	INT = 0,
	 @InvoiceTypeId INT = 0
AS
/*
	 Created: 20150414@Florent
	 Task : get Payer Information by Id
	 DB: DBLIC.bodb_Licensee

	 Revisions:
		+ 20160808@Bravo: Hosting fees
		+ 20160905@Bruce: Default active address is 1
		+ 20161109@Bruce: Include non-official payers
			1: official payer
			5: non-official payer
		+ 20190318@Mason: Add Invoice Language in SELECT statement [#110419]
		+ 20190829@Bruce: Adding Licensee Code [#111586]
		+ 20210315@Happy: Change BaseCurrency Of Licensee [#151466]
		- 20210811@Danny: Adding AttnName2, CompanyName2 into OAS_PartyDetail [#FeatureID 158133]
		- 20210824@Danny: get licensee status from OIC And Relocated SP [#159296]
		- 20201003@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20250321@Eddie: Get more Info "PlatformId" [RedmineID: #217740]
		
	 Params:
	 Example:
		EXEC dbo.LA_PayerInfoSel 14
*/
BEGIN
SET NOCOUNT ON
	DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE())

	CREATE TABLE #tmp_licenseeOIC (RegisteredLicenseeName NVARCHAR(50), LicenseeStatusId TINYINT)
	INSERT INTO #tmp_licenseeOIC(RegisteredLicenseeName, LicenseeStatusId)
	SELECT	RegisteredLicenseeName, LicenseeStatusId
	FROM	DBOIC.bodb_OIC.dbo.licensee WITH(NOLOCK)

	CREATE TABLE #tmp_licenseeOICStatus (LicenseeStatusId TINYINT, LicenseeStatusName NVARCHAR(30))
	INSERT INTO #tmp_licenseeOICStatus(LicenseeStatusId, LicenseeStatusName)
	SELECT	LicenseeStatusId, LicenseeStatusName
	FROM	DBOIC.bodb_OIC.dbo.LicenseeStatus WITH(NOLOCK)

	SELECT TOP 1 p.PartyID AS PayerID
		, p.PartyName AS PayerName
		, pd.StatusId
		, pd.IsDeposit
		, pd.BrandName
		, pd.CompanyName
		, pd.AttnName
		, pd.Description
		, pd.Address1
		, pd.Address2
		, ISNULL(i.ActiveAddress, 1) AS ActiveAddress
		, p.PartyType
		, ISNULL(p.SetupName, '') AS SetupName
		, pd.InvoiceLanguage
		, pd.AttnName2
		, pd.CompanyName2
		, CASE WHEN t.IsDeposit = 0 THEN 'Active'
				 ELSE ISNULL(us.LicenseeStatusName, 'Unrecognized') END AS PayerStatusName
		, p.PlatformId
	FROM dbo.OAS_Party p WITH (NOLOCK)
		LEFT JOIN	dbo.Licensees t WITH(NOLOCK) ON p.OldRefID = t.LicenseeId
		LEFT JOIN	#tmp_licenseeOIC u WITH(NOLOCK) ON t.LicenseeName = u.RegisteredLicenseeName
		LEFT JOIN	#tmp_licenseeOICStatus us WITH(NOLOCK) ON u.LicenseeStatusId = us.LicenseeStatusId
		LEFT JOIN	dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN (
			SELECT i.FromPartyId, i.ToPartyId, i.InvTypeId, ActiveAddress
			FROM dbo.LA_InvoiceSetting i
			WHERE (@BillerId = 0 OR i.ToPartyId = @BillerId) AND (@InvoiceTypeId = 0 OR InvTypeId = @InvoiceTypeId)
			GROUP BY i.FromPartyId, i.ToPartyId, i.InvTypeId, i.ActiveAddress
		) i ON p.PartyID = i.FromPartyId
	WHERE (@PayerId = 0 OR p.PartyID = @PayerId)
		AND p.PartyType IN (1,5)
		
	SELECT p.PartyID
		, p.BaseCurrencyId
		, CASE WHEN p.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END AS BaseCurrencyName
		, p.LicenseeCode
		, p.FromDate
		, p.ToDate
		, CASE WHEN p.ToDate < @CurrentDate THEN 0 ELSE 1 END AS IsActive
	FROM OAS_PartyBaseCurrency p WITH(NOLOCK)
	LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON p.BaseCurrencyId = e.exchangeid
	WHERE PartyID = @PayerId
	ORDER BY p.ToDate DESC

	DROP TABLE #tmp_licenseeOIC
	DROP TABLE #tmp_licenseeOICStatus
END
GO