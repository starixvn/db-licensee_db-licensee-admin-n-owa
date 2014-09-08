USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_FunctionSel]    Script Date: 9/8/2014 4:51:24 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_FunctionSel] 	
AS

/*  
	 Created: 20140814@Florent
	 Task : Select Function list 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params :	 

*/
SET NOCOUNT ON
	
BEGIN	
SELECT	
	   f.FunctionID
	   ,FunctionName
	   ,FunctionDesc
	   ,ParentID
	   ,ParentName
	   ,URL
	   ,CreatedDate
	   ,ModifiedDate
	   ,DisplayOrder
	   ,Creator
	   ,f.StatusID AS IsActive
	   ,FunctionKey	
	   ,Stuff((SELECT ', ' + g.GroupName 
				FROM dbo.LA_GroupFunction gf WITH(NOLOCK) LEFT JOIN dbo.LA_Group g WITH(NOLOCK) ON gf.GroupID = g.GroupID 
				WHERE f.FunctionID = gf.FunctionID
				FOR XML PATH('')),1,1,''
			) GroupName
FROM
	   dbo.LA_Function AS f WITH(NOLOCK)	   

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_FunctionSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_FunctionSel] TO bodbAdminNet 
