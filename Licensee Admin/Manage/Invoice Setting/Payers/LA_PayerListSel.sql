/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerListSel]
	@PayerId		INT			 = 0
   ,@PayerStatusIds	VARCHAR(100) = ''
   ,@PlatformIds	VARCHAR(100) = ''
AS
/*
	Created: 20150414@Florent
	Task : get List Payer by all or by Id
	DB: DBLIC.bodb_Licensee  

	Revisions:
		- 20150917@Victor: support Chinese on settings
		- 20161109@bruce.bui: include non-official payers
		- 20210824@Danny: get licensee status from OIC and relocated SP [#159296]
		- 20241120@Danny: replace strsplit function [RemineID: #212252]
		- 20250321@Eddie: Get more Info PlatformId and get info follow status [RedmineID: #217740]

	Params:
		+ 0 get all payer
		+ <> 0 specify a payer

		+ @PayerStatus: 1	Up Coming
						2	Soft Launch
						3	Active
						4	Terminated
						5	Cancelled
						6	Suspended
						999	Unrecognized
	Example:
		EXEC dbo.LA_PayerListSel 0
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @statusTab TABLE (StatusId SMALLINT)
	INSERT INTO @statusTab (StatusId)
	SELECT CAST(value AS SMALLINT) FROM STRING_SPLIT(@PayerStatusIds,',')

	DECLARE @Payer_Platform TABLE (PlatformId TINYINT)
	INSERT INTO @Payer_Platform (PlatformId)
	SELECT CAST(value AS TINYINT) FROM STRING_SPLIT(@PlatformIds,',')
	
	CREATE TABLE #tmp_licenseeOIC (RegisteredLicenseeName NVARCHAR(50), LicenseeStatusId TINYINT)
	INSERT INTO #tmp_licenseeOIC(RegisteredLicenseeName, LicenseeStatusId)
	SELECT	RegisteredLicenseeName, LicenseeStatusId
	FROM	DBOIC.bodb_OIC.dbo.licensee WITH(NOLOCK)

	CREATE TABLE #tmp_licenseeOICStatus (LicenseeStatusId TINYINT, LicenseeStatusName NVARCHAR(30))
	INSERT INTO #tmp_licenseeOICStatus(LicenseeStatusId, LicenseeStatusName)
	SELECT	LicenseeStatusId, LicenseeStatusName
	FROM	DBOIC.bodb_OIC.dbo.LicenseeStatus WITH(NOLOCK)

	CREATE TABLE #tmp_LA_BillerInfo (PartyId INT, BillerName NVARCHAR(50))
	INSERT INTO #tmp_LA_BillerInfo(PartyId, BillerName)
	SELECT	PartyId, BillerName
	FROM	DBCUST.bodb_licensee.dbo.LA_BillerInfo WITH(NOLOCK)


	;WITH cte_BillerPayer(FromPartyId, ToPartyID) AS
	(
		SELECT FromPartyId, ToPartyID 
		FROM dbo.LA_InvoiceSetting WITH (NOLOCK)
		GROUP BY FromPartyId, ToPartyID
	), cte_BillerPayer_info AS 
	(
	SELECT p.PartyID AS PayerID
			, p.PartyName AS PayerName
			, pd.BrandName
			, pd.CompanyName
			, COUNT(i.ToPartyId) AS NumberOfBillers
			, STUFF((
				SELECT ', ' + CAST(b.BillerName AS NVARCHAR)
				FROM cte_BillerPayer ii
					LEFT JOIN #tmp_LA_BillerInfo b ON ii.ToPartyId = b.PartyId
				WHERE b.PartyID = ii.ToPartyID AND ii.FromPartyId = p.PartyID
				FOR XML PATH ('')
			), 1, 2, '') AS BillerList
			, ISNULL(pd.StatusId,0) AS StatusId
			, p.PartyType
			,CASE WHEN ISNULL(p.PlatformId, 2) <> 2 AND l.IsDeposit = 0 THEN 'Active'
				  WHEN p.PlatformId = 2 AND pd.LaunchDate IS NOT NULL AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL THEN 'Active'
				  WHEN p.PlatformId = 2 AND pd.SuspendedDate IS NOT NULL AND pd.TerminatedDate IS NULL THEN 'Suspended'
				  WHEN p.PlatformId = 2 AND pd.TerminatedDate IS NOT NULL THEN 'Terminated'
			 ELSE ISNULL(oict.LicenseeStatusName, 'Unrecognized') END AS PayerStatusName
			,CASE WHEN ISNULL(p.PlatformId, 2) <> 2 AND l.IsDeposit = 0 THEN 3
				  WHEN p.PlatformId = 2 AND pd.LaunchDate IS NOT NULL AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL THEN 3
				  WHEN p.PlatformId = 2 AND pd.SuspendedDate IS NOT NULL AND pd.TerminatedDate IS NULL THEN 6
				  WHEN p.PlatformId = 2 AND pd.TerminatedDate IS NOT NULL THEN 4
				  WHEN oict.LicenseeStatusId IS NULL THEN 999
			 ELSE oict.LicenseeStatusId END AS PayerStatusId
			, p.PlatformId
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN dbo.Licensees l WITH (NOLOCK) ON p.OldRefID = l.LicenseeID
		LEFT JOIN #tmp_licenseeOIC oic WITH(NOLOCK) ON oic.RegisteredLicenseeName = l.LicenseeName
		LEFT JOIN #tmp_licenseeOICStatus oict ON oic.LicenseeStatusId = oict.LicenseeStatusId
		LEFT JOIN cte_BillerPayer i ON i.FromPartyId = p.PartyID
	WHERE p.PartyType IN (1,5)
		AND (@PayerId = 0 OR p.PartyID = @PayerId)
	GROUP BY p.PartyID, p.PartyName, pd.BrandName, pd.CompanyName, pd.StatusId, p.PartyType, p.PlatformId, 
			CASE WHEN ISNULL(p.PlatformId, 2) <> 2 AND l.IsDeposit = 0 THEN 'Active'
				 WHEN p.PlatformId = 2 AND pd.LaunchDate IS NOT NULL AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL THEN 'Active'
				 WHEN p.PlatformId = 2 AND pd.SuspendedDate IS NOT NULL AND pd.TerminatedDate IS NULL THEN 'Suspended'
				 WHEN p.PlatformId = 2 AND pd.TerminatedDate IS NOT NULL THEN 'Terminated'
			 ELSE ISNULL(oict.LicenseeStatusName, 'Unrecognized') END,
			CASE WHEN ISNULL(p.PlatformId, 2) <> 2 AND l.IsDeposit = 0 THEN 3
				 WHEN p.PlatformId = 2 AND pd.LaunchDate IS NOT NULL AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL THEN 3
				 WHEN p.PlatformId = 2 AND pd.SuspendedDate IS NOT NULL AND pd.TerminatedDate IS NULL THEN 6
				 WHEN p.PlatformId = 2 AND pd.TerminatedDate IS NOT NULL THEN 4
				 WHEN oict.LicenseeStatusId IS NULL THEN 999
			 ELSE oict.LicenseeStatusId END
	)
	SELECT bi.PayerID, bi.PayerName, bi.BrandName, bi.CompanyName, bi.NumberOfBillers, bi.BillerList, bi.StatusId, bi.PartyType, bi.PayerStatusName, bi.PlatformId, f.PlatformName
	FROM cte_BillerPayer_info bi
		INNER JOIN dbo.LA_f_PayerPlatform_Sel() f ON f.PlatformId = bi.PlatformId
	WHERE bi.PayerStatusId IN (SELECT x.StatusId FROM @statusTab x)
	  AND bi.PlatformId IN ( SELECT PlatformId FROM @Payer_Platform )


	DROP TABLE #tmp_licenseeOIC
	DROP TABLE #tmp_licenseeOICStatus
	DROP TABLE #tmp_LA_BillerInfo
	-- PartyType
	--
	-- 1: official licensee (unmapped)
	-- 5: non-offcial licensee
END
GO