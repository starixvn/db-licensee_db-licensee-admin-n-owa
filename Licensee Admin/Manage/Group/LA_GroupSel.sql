USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_GroupSel]    Script Date: 9/12/2014 11:09:41 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_GroupSel] 
    @GroupID INT = - 1
AS

/*  
	 Created: 20140819@Florent
	 Task : Select Group list 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
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
GRANT VIEW DEFINITION ON [dbo].[LA_GroupSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_GroupSel] TO bodbAdminNet 
