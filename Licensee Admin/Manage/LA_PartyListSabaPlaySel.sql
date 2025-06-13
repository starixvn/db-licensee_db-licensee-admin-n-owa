/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[LA_PartyListSabaPlaySel]
	@UserID			INT = 0
   ,@FunctionKey	NVARCHAR(100) = ''
AS
/*
	Created: 20250321@Eddie
	DB: DBLIC-bodb_Licensee,DBCUST-bodb_Licensee
	Task : Get list of SabaPlay payer

	Revisions:
		- 20250321@Eddie: Initialize SP [RedmineID: #217740]
		- 20250611@Eddie: Enhancement SP [#229500]

	Current settings:
			1	 : ONEWorks Licensees
			9	 : Cozni Licensees
			11	 : Boping Licensees
			98	 : Zelianta Licensees
			962	 : JollySports Licensees
			1235 : Double S Licensees
			999	 : Credit Licensees
			1000 : Non-Official Licensees
	Params:
		+ UserID:
			- 0 : get list SabaPlay Party of All User
		+ FunctionKey:
			-'' : get list SabaPlay Party when config in Manage User
	Example:
		EXEC dbo.LA_PartyListSabaPlay
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @FunctionID INT

	IF(@FunctionKey = '')
	BEGIN
		SET @FunctionID = 0
	END
	ELSE
	BEGIN
		SELECT @FunctionID = FunctionID FROM LA_Function WITH(NOLOCK) WHERE FunctionKey = @FunctionKey
	END

	CREATE TABLE #data ( PartyID   INT
						,PartyName NVARCHAR(100)
						,BrandName NVARCHAR(100)
						,ParentID  INT )
	
	IF (@FunctionID = 0 AND @UserID > 0) --get list Party of 1 User
	BEGIN

		INSERT INTO #data (PartyID, PartyName, BrandName, ParentID)
		SELECT p.PartyID, p.PartyName, d.BrandName, 9999 AS ParentID
		FROM dbo.LA_UserParty up WITH (NOLOCK)
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON up.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
		WHERE up.UserID = @UserID
		  AND p.PartyType = 1 AND p.PlatformId = 2

	END
	ELSE IF (@FunctionID > 0 AND @UserID = 0) --get list Party assign to 1 Function
	BEGIN

		INSERT INTO #data (PartyID, PartyName, BrandName, ParentID)
		SELECT p.PartyID, p.PartyName, d.BrandName, 9999 AS ParentID
		FROM dbo.LA_FunctionParty fp WITH (NOLOCK)
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON fp.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
		WHERE fp.FunctionID = @FunctionID
		  AND p.PartyType = 1 AND p.PlatformId = 2

	END
	ELSE IF (@FunctionID > 0 AND @UserID > 0) --get Party List By User and Function
	BEGIN

		INSERT INTO #data (PartyID, PartyName, BrandName, ParentID)
		SELECT p.PartyID, p.PartyName, d.BrandName, 9999 AS ParentID
		FROM dbo.LA_UserParty up WITH (NOLOCK)
			INNER JOIN dbo.LA_UserFunction uf WITH (NOLOCK) ON up.UserID = uf.UserID
			INNER JOIN dbo.LA_FunctionParty fp WITH (NOLOCK) ON up.PartyID = fp.PartyID AND uf.FunctionID = fp.FunctionID
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON up.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
		WHERE up.UserID = @UserID
		  AND fp.FunctionID = @FunctionID
		  AND p.PartyType = 1 AND p.PlatformId = 2
	END
	ELSE
	BEGIN

		INSERT INTO #data (PartyID, PartyName, BrandName, ParentID)
		SELECT p.PartyID, p.PartyName, d.BrandName, 9999 AS ParentID
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
		WHERE p.PartyType = 1 AND p.PlatformId = 2

	END
	
	SELECT t.PartyID, t.PartyName, t.BrandName, t.ParentID
	FROM (
		SELECT PartyID, PartyName, BrandName, ParentID
		FROM #data
	
		UNION ALL

		SELECT 9999, 'Reasternhold Licensees', '', 0
	) AS t
	ORDER BY t.ParentID, t.PartyID

	DROP TABLE #data
END
GO