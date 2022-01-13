/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFee_AvailablePartyListSel]
	@GroupMinFeeId	SMALLINT = 0,
	@FromDate	DATE = NULL, 
	@ToDate		DATE = NULL
AS
/*  
	 Created: 20200702@Mason [#134492]
	 Task : Get available parties for group min fee
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20200702@Mason: Implement Group Min Fee [#134492]
		- 20210824@Danny: get licensee status from OIC And Relocated SP [#159296]

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	DECLARE @PayerList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100))
	DECLARE @PartySettings TABLE(GroupMinFeeId INT, PartyId INT, ProductId INT)

	
	CREATE TABLE #tmp_licenseeOIC (RegisteredLicenseeName NVARCHAR(50), LicenseeStatusId TINYINT)
	INSERT INTO #tmp_licenseeOIC(RegisteredLicenseeName, LicenseeStatusId)
	SELECT	RegisteredLicenseeName, LicenseeStatusId
	FROM	DBOIC.bodb_OIC.dbo.licensee WITH(NOLOCK) WHERE LicenseeStatusId = 3

	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	INSERT INTO @PartySettings(GroupMinFeeId, PartyId)
	SELECT DISTINCT h.GroupMinFeeID, a.PartyId
	FROM dbo.LA_GroupMinFeeHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON a.GroupMinFeeID = h.GroupMinFeeID
	WHERE (@FromDate IS NULL OR @FromDate <= h.ToDate) AND (@ToDate IS NULL OR @ToDate >= h.FromDate)
			AND (@GroupMinFeeId = 0 OR h.GroupMinFeeID = @GroupMinFeeId)
		
	INSERT INTO @PayerList(PartyId, PartyName, BrandName)
	--list of payer not in group
	SELECT p.PartyId, PartyName, BrandName
	FROM @PartyList p
	WHERE p.PartyId NOT IN (SELECT PartyId 
							FROM @PartySettings)
		AND p.ParentId NOT IN (0, 999)
		
	UNION

	--list of payer in group
	SELECT p.PartyId, PartyName, BrandName
	FROM @PartyList p
	WHERE p.PartyId IN (SELECT PartyId 
						FROM @PartySettings p1)
		AND p.ParentId NOT IN (0, 999)

	SELECT  p.PartyId, p.PartyName, p.BrandName
	FROM		@PayerList p
	INNER JOIN  dbo.OAS_Party op WITH(NOLOCK) ON p.PartyId = op.PartyID
	INNER JOIN  dbo.Licensees l WITH(NOLOCK) ON l.LicenseeID = op.OldRefID
	INNER JOIN	#tmp_licenseeOIC oic WITH(NOLOCK) ON oic.RegisteredLicenseeName = l.LicenseeName

	DROP TABLE #tmp_licenseeOIC
END
GO