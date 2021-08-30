/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PartyListTerminatedSel]
	@UserID		INT	   = 0
AS
/*
	Created: 20170223@scofield.huynh
	Task : Get list of terminated payers [#70050]
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20170223@Scofield: Initialize SP
		- 20190802@Parsons: Validate billing configuration [#109600]
		- 20190920@Bruce: fix bug: show all terminated licensees [#118627]
		- 20210823@Danny: filter licensee status from OIC AND relocated SP [#159296]

	Params:
	Example:
		EXEC dbo.LA_PartyListTerminatedSel
*/
BEGIN
	SET NOCOUNT ON

	-- current settings:
	--
	-- 1	: ONEWorks Licensees
	-- 11	: Boping Licensees
	-- 98	: Zelianta Licensees
	-- 999	: Credit Licensees
	-- 1000	: Non-Official Licensees

	-- new settings
	--
	-- 1001	: Terminated Licensees

	SELECT p.PartyID, p.PartyName, d.BrandName, 1001 AS ParentID
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
	INNER JOIN dbo.Licensees l WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	INNER JOIN bodb_OIC.dbo.Licensee oic WITH(NOLOCK) ON oic.RegisteredLicenseeName = l.LicenseeName
	WHERE (@UserID = 0 OR p.PartyID IN (
		SELECT up.PartyID FROM dbo.LA_UserParty up WITH (NOLOCK) WHERE up.UserID = @UserID
	)) 
	AND p.PartyType = 1 AND d.IsDeposit = 1 AND d.StatusId = 1 AND oic.LicenseeStatusId = 4

	UNION ALL

	SELECT 1001, 'Terminated Licensees', '', 0
END
GO