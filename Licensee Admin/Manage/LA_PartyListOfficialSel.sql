/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].[LA_PartyListOfficialSel]
	 @UserID		INT	   = 0,
	 @FunctionID	INT	   = 0
AS

/*
	Created: 20190731@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190731@Parsons: Validate billing configuration [#109600]
*/

SET NOCOUNT ON

	;WITH cte_TerminatedPartyIds AS(
		SELECT FromParty AS PartyId
				FROM OAS_ChargeInfo WITH(NOLOCK)
				WHERE ChargeType NOT IN (2, 3) -- Old type & No longer used
				GROUP BY FromParty
				HAVING MAX(ToDate) < CONVERT(DATE, GETDATE())
	)
	SELECT DISTINCT p.PartyID, p.PartyName, d.BrandName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
		INNER JOIN dbo.LA_UserParty up WITH (NOLOCK) ON p.PartyID = up.PartyID
		INNER JOIN dbo.LA_FunctionParty fp WITH (NOLOCK) ON p.PartyID = fp.PartyID 
	WHERE p.PartyID NOT IN ( SELECT PartyId FROM cte_TerminatedPartyIds) AND
		  p.PartyType = 1 AND d.IsDeposit = 1 AND d.StatusId = 1 AND 
		  (@UserID = 0 OR up.UserID = @UserID) AND 
		  (@FunctionID = 0 OR fp.FunctionID = @FunctionID)
GO