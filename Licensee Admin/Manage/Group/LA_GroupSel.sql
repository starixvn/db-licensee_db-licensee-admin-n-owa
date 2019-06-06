/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupSel] 
    @GroupID INT = - 1
AS

/*  
	 Created: 20140819@Florent
	 Task : Select Group list 
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20140819@Florent: Initialize SP
*/
SET NOCOUNT ON
BEGIN	
    SELECT
		g.GroupID,
		g.GroupName,
		g.GroupDesc,			
		g.StatusID		
	FROM
		dbo.LA_Group AS g WITH(NOLOCK)		
	WHERE ( @GroupID <= 0 OR g.GroupID = @GroupID )
		 --AND g.GroupID > 0
     ORDER BY g.GroupID DESC
END
GO