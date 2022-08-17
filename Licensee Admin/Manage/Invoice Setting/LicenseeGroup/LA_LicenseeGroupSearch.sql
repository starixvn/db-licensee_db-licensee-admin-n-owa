/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_LicenseeGroupSearch]
	@Username VARCHAR(100) = ''
AS
/*  
	 Created: 20220817@Malcolm
	 Task : LA - Invoice - Manage Licensee Group - Search [RedminId : #176437]
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20220817@Malcolm: Initialize SPs
*/

BEGIN
	SET NOCOUNT ON
	
	SELECT @Username = ISNULL(@Username, '')

	CREATE TABLE #Group (GroupId INT PRIMARY KEY, GroupName NVARCHAR(30), ParentId INT, PartyNames VARCHAR(MAX), IsDeleted BIT DEFAULT(1))

	INSERT INTO #Group (GroupId, GroupName, ParentId)
	SELECT c.GroupId, c.GroupName, ISNULL(p.GroupId, 0) AS ParentId
	FROM dbo.LA_CombinedGroup c WITH(NOLOCK)
		LEFT JOIN dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')
	WHERE (c.PathCode = '/'	OR p.GroupId IS NOT NULL)

	;WITH CTE AS (
		SELECT DISTINCT 
			ISNULL(g.GroupId, 0) AS GroupId
			,p.PartyName
			,CASE WHEN p.PartyName LIKE '%'+ @Username +'%' THEN 0 ELSE 1 END AS IsDeleted
		FROM dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID=pd.PartyID
			LEFT JOIN dbo.LA_CombinedGroupAssignment g WITH(NOLOCK) ON g.PartyId = p.PartyID
		WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND pd.StatusId = 1
	),
	GroupParty AS (
		SELECT GroupId, STRING_AGG(LTRIM(RTRIM(PartyName)), ',') AS PartyNames, MIN(IsDeleted) AS IsDeleted
		FROM CTE e
		GROUP BY GroupId
	)
	UPDATE g
		SET g.PartyNames = p.PartyNames, g.IsDeleted = p.IsDeleted
	FROM #Group g
		INNER JOIN GroupParty p ON p.GroupId = g.GroupId

	IF @Username <> ''
	BEGIN
		DELETE g
		FROM #Group g
		WHERE g.GroupName NOT LIKE '%' + @Username + '%' AND g.IsDeleted = 1
	END

	SELECT GroupId, GroupName, ParentId, PartyNames 
	FROM #Group
	ORDER BY GroupName ASC
	
	DROP TABLE #Group
END
GO