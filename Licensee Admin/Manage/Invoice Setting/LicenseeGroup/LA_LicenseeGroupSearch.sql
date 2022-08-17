/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].[LA_LicenseeGroupSearch]
	@Username VARCHAR(100)
	,@IsActive BIT = 0
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP
*/

BEGIN
	SET NOCOUNT ON
	
	SELECT @IsActive = ISNULL(@IsActive, 0), @Username = ISNULL(@Username, '')

	DECLARE @PartyInfo TABLE (PartyId INT,PartyName VARCHAR(50), GroupId INT)

	INSERT INTO @PartyInfo (PartyId, PartyName, GroupId)
	SELECT 
		p.PartyId
		,p.PartyName
		,ISNULL(a.GroupId, 0) AS GroupId
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID=pd.PartyID
		LEFT JOIN dbo.LA_CombinedGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId
	WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND pd.StatusId = 1
	AND (@IsActive = 0 OR @IsActive = 1 AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL)
	AND (p.PartyName LIKE '%' + @Username + '%' OR @Username = '')

	SELECT c.GroupId, c.GroupName, ISNULL(p.GroupId, 0) AS ParentId
	FROM dbo.LA_CombinedGroup c WITH(NOLOCK)
	LEFT JOIN dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')
	WHERE (c.PathCode = '/'	OR p.GroupId IS NOT NULL)
		AND c.GroupName LIKE ''

END
GO