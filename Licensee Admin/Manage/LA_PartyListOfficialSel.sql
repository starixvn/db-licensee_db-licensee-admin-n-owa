/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_PartyListOfficialSel]
	 @UserID		INT	   = 0,
	 @FunctionKey	NVARCHAR(100)	= ''
AS

/*
	Created: 20190731@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190731@Parsons: Validate billing configuration [#109600]
	- 20190821@Parsons: Enhancement for code release process [#118627]
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
		INNER JOIN dbo.LA_Function f WITH(NOLOCK) ON fp.FunctionID = f.FunctionID
	WHERE p.PartyID NOT IN ( SELECT PartyId FROM cte_TerminatedPartyIds) AND
		  p.PartyType = 1 AND d.IsDeposit = 1 AND d.StatusId = 1 AND 
		  (@UserID = 0 OR up.UserID = @UserID) AND 
		  (@FunctionKey = '' OR f.FunctionKey = @FunctionKey)

	UNION 

	SELECT b.PartyID, ISNULL(b.BillerName, p.PartyName) AS PartyName, '' AS BrandName
	FROM dbo.LA_BillerInfo b WITH (NOLOCK)
		LEFT JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = b.PartyID 
GO