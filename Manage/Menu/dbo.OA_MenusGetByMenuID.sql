ALTER PROCEDURE [dbo].[OA_MenusGetByMenuID]
	@MenuID INT
AS
/*  
 * Created: 20111014@Lewis
 * Task : Get a specific menu by its id
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
SET NOCOUNT ON

SELECT	
	 m.MenuID
	,m.MenuName
	,m.MenuDesc
	,m.ParentID
	,m.ParentName
	,m.URL
	,m.CreatedDate
	,m.ModifiedDate
	,m.DisplayOrder
	,m.Creator
	,m.IsActive
	,f.FunctionID
	,f.FunctionName
	,m.Policy

FROM
	dbo.OA_Menus AS m WITH (NOLOCK)
JOIN
	dbo.OA_Functions f WITH (NOLOCK)
ON  m.FunctionID = f.FunctionID

WHERE m.MenuID = @MenuID
	

GO
GRANT EXECUTE ON [dbo].[OA_MenusGetByMenuID] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_MenusGetByMenuID] TO [vnteam]
 