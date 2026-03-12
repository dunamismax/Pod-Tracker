import { QueryClient, queryOptions } from "@tanstack/react-query";

import { getDashboard, getViewer } from "./server-fns";

export const createQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        gcTime: 5 * 60_000,
        refetchOnWindowFocus: false,
      },
    },
  });

export const viewerQueryOptions = () =>
  queryOptions({
    queryKey: ["viewer"],
    queryFn: () => getViewer(),
  });

export const dashboardQueryOptions = () =>
  queryOptions({
    queryKey: ["dashboard"],
    queryFn: () => getDashboard(),
  });
