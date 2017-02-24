USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PartyListTerminatedSel]
	@UserID		INT	   = 0
AS
/*
	Created: 20170223@scofield.huynh
	Task : Get list of terminated payers
	DB: DB052.bodb_Licensee

	Revisions:
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
	INNER JOIN dbo.LA_UserParty up WITH (NOLOCK) ON p.PartyID = up.PartyID
	WHERE p.PartyID IN (
		SELECT FromParty 
		FROM (SELECT FromParty AS FromParty, MAX(ToDate) AS ToDate 
			  FROM OAS_ChargeInfo
			  GROUP BY FromParty) candidateParties
		WHERE ToDate < CONVERT(DATE, GETDATE())
	) AND p.PartyType = 1 AND d.IsDeposit = 1 AND d.StatusId = 1 AND up.UserID = @UserID

	UNION ALL

	SELECT 1001, 'Terminated Licensees', '', 0
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_PartyListTerminatedSel] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_PartyListTerminatedSel] TO bodbAdminNet
