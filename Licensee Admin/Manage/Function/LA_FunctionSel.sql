/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_FunctionSel] 	
AS

/*  
	 Created: 20140814@Florent
	 Task : Select Function list 
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20140814@Florent: Initialize SP

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